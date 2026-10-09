"""Builds halo-stt-vi.zip, the speech-model package customers import in Halo.

Usage:
    python -I tool/make_stt_package.py <extracted-model-dir> <output.zip>

<extracted-model-dir> is the official
sherpa-onnx-zipformer-vi-int8-2025-04-20 release, extracted. Only the four
files Halo needs are packaged, each verified against the SHA-256 that the
app also checks (lib/features/model_setup/data/model_catalog.dart). The
release's test_wavs/ (non-commercial source) are never included.
"""

import hashlib
import os
import sys
import zipfile

FILES = {
    "encoder-epoch-12-avg-8.int8.onnx": (70876129, "b3abdef7a660fea7faf5e076b3c7613b0fc98406707103784d018189bb522124"),
    "decoder-epoch-12-avg-8.onnx": (5165084, "d1d27cca84c824a8acf5ce6edf0f2c0880cfe295d2e69b95134de1707e1d9998"),
    "joiner-epoch-12-avg-8.int8.onnx": (1033417, "38ec49e1c18e4feb0cad4de13e25c83a866cf56f4a66f22e8ff579d591a69a46"),
    "tokens.txt": (25847, "f536d03c2e95ebd2930cf0abec88e823bd17d3c1933da7ae6a82db3b80605e15"),
}

NOTICE = """Vietnamese speech recognition model for Halo (offline).

Model: sherpa-onnx-zipformer-vi-int8-2025-04-20, converted by the k2-fsa
sherpa-onnx project (https://github.com/k2-fsa/sherpa-onnx) from
https://huggingface.co/zzasdf/viet_iter3_pseudo_label.
Licence: Apache License, Version 2.0 (full text in the app: History > i).

Import this ZIP in Halo: History > AI models > Vietnamese speech model >
Import. Do not unzip it.
"""


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main(source, output):
    for name, (size, digest) in FILES.items():
        path = os.path.join(source, name)
        if os.path.getsize(path) != size or sha256(path) != digest:
            sys.exit(f"{name}: size or SHA-256 does not match the official file")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name in FILES:
            z.write(os.path.join(source, name), arcname=f"halo-stt-vi/{name}")
        z.writestr("halo-stt-vi/NOTICE.txt", NOTICE)
    print(f"{output}: {os.path.getsize(output)} bytes, sha256 {sha256(output)}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
