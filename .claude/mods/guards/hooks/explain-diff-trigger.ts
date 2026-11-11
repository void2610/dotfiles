// 番号だけの数は課題番号などと区別できないので、# 付き・PR・URL のどれかで PR と判定する
const PR_REF_RE = /#\d{3,}|\bPR\b|プルリク|\/pull\/\d+/;
const PR_REVIEW_RE = /レビュー|review|解説|説明/i;
const NEXT_PR_RE = /次の.{0,12}PR/;
// 長い手順書で他システムの #番号と別の文の「レビュー」が組にならないよう文単位で見る (URL と依頼を改行で分けて書く形があるので改行では区切らない)
const SENTENCE_END_RE = /[。！!]/;
// 一覧の依頼・自動化の話・質問 (ファイルを作らない) は対象にしない
const NOT_PR_REVIEW_RE =
  /待ち|まとめ|一覧|キュー|溜ま|スキル|フック|自動|[?？]\s*$/;
// pr-watch の起床文やタスク通知も「PR」「レビュー」を含むため、文面ではなく投入元で除く
const HUMAN_ORIGINS = new Set(["composer", "bridge", "sdk", "slack-ping"]);
const MSG =
  "PR のレビュー・解説の依頼を検知した。レビュー本体と同じ手番で explain-diff-html スキルを発動し、その PR の解説ページを作れ。";

export const isPrReviewRequest = (text: string): boolean =>
  !NOT_PR_REVIEW_RE.test(text) &&
  (NEXT_PR_RE.test(text) ||
    text
      .split(SENTENCE_END_RE)
      .some((s) => PR_REF_RE.test(s) && PR_REVIEW_RE.test(s)));

export const explainDiffNote = (
  text: string,
  originKind: string,
): string | undefined =>
  HUMAN_ORIGINS.has(originKind) && isPrReviewRequest(text) ? MSG : undefined;
