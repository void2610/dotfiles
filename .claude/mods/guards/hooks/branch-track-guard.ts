// origin/main 起点のブランチ作成は upstream が main に向き、git push が main を狙う事故につながる
const CREATE_FROM_MAIN_RE =
  /\bgit(\s+-C\s+\S+)?\s+(switch\s+(-c|-C|--create)|checkout\s+(-b|-B))\s+\S+\s+origin\/(main|master)\b/;
const NO_TRACK_RE = /\s--no-track\b/;
const SET_UPSTREAM_MAIN_RE =
  /\bgit(\s+-C\s+\S+)?\s+branch\s+(-u|--set-upstream-to)[= ]origin\/(main|master)\b/;

export function branchTrackDeny(cmd: string): string | undefined {
  if (CREATE_FROM_MAIN_RE.test(cmd) && !NO_TRACK_RE.test(cmd)) {
    return "ブランチ作成をブロック: origin/main 起点で作ると upstream が origin/main になり、git push が main を狙う事故につながる。--no-track を付けて作成し、upstream は初回 push 時に 'git push -u origin HEAD' で同名リモートブランチへ紐づけること。";
  }
  if (SET_UPSTREAM_MAIN_RE.test(cmd)) {
    return "upstream 変更をブロック: フィーチャーブランチの upstream を origin/main に向けてはならない。'git push -u origin HEAD' で同名リモートブランチへ紐づけること。";
  }
  return undefined;
}
