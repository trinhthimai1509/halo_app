package dev.offlineai.offline_ai_chat

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FilterInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

/**
 * Model import over the Storage Access Framework (no storage permission).
 *
 * - `pick`: system file picker (ACTION_OPEN_DOCUMENT), one or many files.
 * - `copy`: streams one picked document to a private file, hashing (SHA-256)
 *   on the fly; never holds the file in memory.
 * - `extractZip`: streams a picked ZIP and writes only the wanted entries
 *   (by file name, any folder) into a private directory, hashing each.
 * - `cancel`, `freeBytes`; progress events on `halo/model_import/progress`.
 *
 * All file I/O runs on a background thread; results return on the main
 * thread. Partial output is deleted on failure or cancellation.
 */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val cancelled = ConcurrentHashMap<String, Boolean>()
    private var progressSink: EventChannel.EventSink? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "halo/model_import").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(call, result)
                "copy" -> runJob(call, result) { job -> copy(call, job) }
                "extractZip" -> runJob(call, result) { job -> extractZip(call, job) }
                "cancel" -> {
                    cancelled[call.argument<String>("jobId")!!] = true
                    result.success(null)
                }
                "freeBytes" -> {
                    val dir = File(call.argument<String>("path")!!)
                    dir.mkdirs()
                    result.success(StatFs(dir.path).availableBytes)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "halo/model_import/progress").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    progressSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            },
        )
    }

    // ---- picking ----

    private fun pick(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*" // .gguf/.onnx have no registered MIME type
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") == true)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, PICK_REQUEST)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else {
            data.data?.let { uris.add(it) }
        }
        result.success(uris.map { describe(it) })
    }

    private fun describe(uri: Uri): Map<String, Any?> {
        var name: String? = null
        var size: Long? = null
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s = c.getColumnIndex(OpenableColumns.SIZE)
                if (n >= 0) name = c.getString(n)
                if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
            }
        }
        return mapOf("uri" to uri.toString(), "name" to (name ?: "file"), "size" to size)
    }

    // ---- jobs ----

    private class Cancelled : Exception("cancelled")

    private fun runJob(call: MethodCall, result: MethodChannel.Result, work: (String) -> Any?) {
        // Job ids are unique per import; a cancel that arrives before the
        // job starts must stick, so the flag is only cleared afterwards.
        val job = call.argument<String>("jobId")!!
        io.execute {
            try {
                val value = work(job)
                main.post { result.success(value) }
            } catch (e: Cancelled) {
                main.post { result.error("cancelled", "Import cancelled.", null) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message ?: e.javaClass.simpleName, null) }
            } finally {
                cancelled.remove(job)
            }
        }
    }

    private fun checkCancelled(job: String) {
        if (cancelled[job] == true) throw Cancelled()
    }

    private var lastEvent = 0L

    private fun progress(job: String, bytes: Long, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastEvent < 100) return
        lastEvent = now
        main.post { progressSink?.success(mapOf("jobId" to job, "bytes" to bytes)) }
    }

    private fun copy(call: MethodCall, job: String): Map<String, Any> {
        val uri = Uri.parse(call.argument<String>("uri"))
        val dest = File(call.argument<String>("dest")!!)
        dest.parentFile?.mkdirs()
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("The file could not be opened.")
            input.use { inp ->
                dest.outputStream().use { out ->
                    val buffer = ByteArray(BUFFER)
                    while (true) {
                        checkCancelled(job)
                        val n = inp.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        digest.update(buffer, 0, n)
                        total += n
                        progress(job, total)
                    }
                    out.fd.sync()
                }
            }
        } catch (e: Exception) {
            dest.delete()
            throw e
        }
        progress(job, total, force = true)
        return mapOf("bytes" to total, "sha256" to hex(digest.digest()))
    }

    private fun extractZip(call: MethodCall, job: String): Map<String, Any> {
        val uri = Uri.parse(call.argument<String>("uri"))
        val destDir = File(call.argument<String>("destDir")!!)
        val wanted = call.argument<List<String>>("names")!!.toSet()
        destDir.mkdirs()
        val found = mutableMapOf<String, Map<String, Any>>()
        val written = mutableListOf<File>()
        try {
            val raw = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("The file could not be opened.")
            val counting = CountingStream(raw) { read -> progress(job, read) }
            ZipInputStream(counting).use { zip ->
                val buffer = ByteArray(BUFFER)
                while (true) {
                    checkCancelled(job)
                    val entry = zip.nextEntry ?: break
                    val name = entry.name.substringAfterLast('/')
                    if (entry.isDirectory || name !in wanted || name in found) continue
                    val target = File(destDir, name)
                    written.add(target)
                    val digest = MessageDigest.getInstance("SHA-256")
                    var size = 0L
                    target.outputStream().use { out ->
                        while (true) {
                            checkCancelled(job)
                            val n = zip.read(buffer)
                            if (n < 0) break
                            out.write(buffer, 0, n)
                            digest.update(buffer, 0, n)
                            size += n
                        }
                        out.fd.sync()
                    }
                    found[name] = mapOf("bytes" to size, "sha256" to hex(digest.digest()))
                }
            }
            progress(job, counting.count, force = true)
        } catch (e: Exception) {
            written.forEach { it.delete() }
            throw e
        }
        return found
    }

    private class CountingStream(input: InputStream, val onRead: (Long) -> Unit) :
        FilterInputStream(input) {
        var count = 0L

        override fun read(): Int {
            val b = super.read()
            if (b >= 0) onRead(++count)
            return b
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            val n = super.read(b, off, len)
            if (n > 0) {
                count += n
                onRead(count)
            }
            return n
        }
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    companion object {
        private const val PICK_REQUEST = 4207
        private const val BUFFER = 1 shl 20 // 1 MiB
    }
}
