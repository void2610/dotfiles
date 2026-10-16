"""PR の diff をファイルごとの patch に分ける。

使い方: split_diff.py <diff.patch> <出力ディレクトリ>
出力: <出力ディレクトリ>/files/<連番>.patch と index.tsv (連番・削除行数・追加行数・種別・パス)
"""

import os
import sys


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, "files"), exist_ok=True)
    chunks = []
    with open(src, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("diff --git"):
                chunks.append({"path": line.split(" b/", 1)[1].strip(), "lines": []})
            if chunks:
                chunks[-1]["lines"].append(line)
    with open(os.path.join(out, "index.tsv"), "w", encoding="utf-8") as idx:
        for i, c in enumerate(chunks):
            body = c["lines"]
            kind = "modified"
            for line in body[:6]:
                if line.startswith("new file"):
                    kind = "new"
                elif line.startswith("deleted file"):
                    kind = "deleted"
                elif line.startswith("rename from"):
                    kind = "renamed"
                elif line.startswith("Binary"):
                    kind = "binary"
            removed = sum(1 for x in body if x.startswith("-") and not x.startswith("---"))
            added = sum(1 for x in body if x.startswith("+") and not x.startswith("+++"))
            name = f"{i:04d}.patch"
            with open(os.path.join(out, "files", name), "w", encoding="utf-8") as fo:
                fo.writelines(body)
            idx.write(f"{name}\t{removed}\t{added}\t{kind}\t{c['path']}\n")


if __name__ == "__main__":
    main()
