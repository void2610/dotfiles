#!/usr/bin/env python3
import base64
import os
import re
import shutil
import sys
from pathlib import Path

# Google ドキュメントの md エクスポートは画像を末尾に参照定義として base64 で埋め込む
DATA_DEF = re.compile(
    r"^\[(?P<id>[^\]]+)\]:\s*<?data:image/(?P<mime>[\w.+-]+);base64,(?P<data>[A-Za-z0-9+/=]+)>?[ \t]*$",
    re.MULTILINE,
)
EXT = {"jpeg": "jpg", "svg+xml": "svg"}


def extract(md: Path) -> bool:
    text = md.read_text(encoding="utf-8")
    if "data:image/" not in text:
        return False

    images_dir = md.with_suffix(".images")
    # 再エクスポート時は画像の増減があり得るので作り直す
    shutil.rmtree(images_dir, ignore_errors=True)
    images_dir.mkdir()

    def replace(m: re.Match) -> str:
        ext = EXT.get(m["mime"], m["mime"])
        name = f"{m['id']}.{ext}"
        (images_dir / name).write_bytes(base64.b64decode(m["data"]))
        return f"[{m['id']}]: <{images_dir.name}/{name}>"

    st = md.stat()
    md.write_text(DATA_DEF.sub(replace, text), encoding="utf-8")
    # rclone は Google ドキュメントをサイズ不明として更新日時で比較するため、元に戻さないと毎回再取得になる
    os.utime(md, ns=(st.st_atime_ns, st.st_mtime_ns))
    return True


def remove_orphans(root: Path) -> None:
    for d in root.rglob("*.images"):
        if d.is_dir() and not d.with_suffix(".md").exists():
            shutil.rmtree(d)


def main() -> None:
    root = Path(sys.argv[1])
    count = sum(extract(md) for md in root.rglob("*.md"))
    remove_orphans(root)
    if count:
        print(f"drive-sync: {count} 件の md から埋め込み画像を切り出しました")


if __name__ == "__main__":
    main()
