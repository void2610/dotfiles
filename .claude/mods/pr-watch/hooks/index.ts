import type { EngineInterface, Register } from "claude-code";

type CiState = "pass" | "fail" | "pending" | "none";

type Watched = {
  prNumber: number;
  lastCi?: CiState;
  notifiedReview: boolean;
  notifiedCiFail: boolean;
};

let watched: Watched | undefined;
let pollerStarted = false;
let tick = 0;

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

function ciStateOf(
  rollup: readonly { state?: string; conclusion?: string; status?: string }[],
): CiState {
  if (rollup.length === 0) return "none";
  const states = rollup.map((c) =>
    (c.conclusion || c.state || c.status || "").toUpperCase(),
  );
  if (
    states.some((s) => s === "FAILURE" || s === "ERROR" || s === "TIMED_OUT")
  ) {
    return "fail";
  }
  if (
    states.some(
      (s) =>
        s === "" ||
        s === "PENDING" ||
        s === "IN_PROGRESS" ||
        s === "QUEUED" ||
        s === "EXPECTED",
    )
  ) {
    return "pending";
  }
  return "pass";
}

async function poll($: EngineInterface): Promise<void> {
  const run = async (argv: readonly string[]) => {
    const r = await $.process.run(argv);
    return r.exitCode === 0 ? r.stdout.trim() : undefined;
  };

  const branch = await run(["git", "rev-parse", "--abbrev-ref", "HEAD"]);
  const defaultBranch = (
    (await run([
      "git",
      "symbolic-ref",
      "--short",
      "refs/remotes/origin/HEAD",
    ])) ?? ""
  ).replace(/^origin\//, "");
  if (!branch || branch === defaultBranch) {
    if (watched) $.ui.status(undefined);
    watched = undefined;
    return;
  }

  const json = await run([
    "gh",
    "pr",
    "view",
    "--json",
    "number,state,statusCheckRollup,reviews",
  ]);
  if (!json) {
    if (watched) $.ui.status(undefined);
    watched = undefined;
    return;
  }
  let pr: {
    number: number;
    state: string;
    statusCheckRollup?: {
      state?: string;
      conclusion?: string;
      status?: string;
    }[];
    reviews?: { author?: { login?: string } }[];
  };
  try {
    pr = JSON.parse(json);
  } catch {
    return;
  }
  if (pr.state !== "OPEN") {
    if (watched) $.ui.status(undefined);
    watched = undefined;
    return;
  }

  const copilotReviews = (pr.reviews ?? []).filter((r) =>
    (r.author?.login ?? "").startsWith("copilot"),
  ).length;

  if (!watched || watched.prNumber !== pr.number) {
    watched = {
      prNumber: pr.number,
      notifiedReview: false,
      notifiedCiFail: false,
    };
  }
  const w = watched;

  const ci = ciStateOf(pr.statusCheckRollup ?? []);
  // ポーリングが生きていることを示すため、回転グリフ付きで status 行に常時表示する
  tick = (tick + 1) % SPINNER.length;
  const review = w.notifiedReview
    ? "レビュー通知済"
    : copilotReviews > 0
      ? "レビュー到着"
      : "レビュー待ち";
  $.ui.status(`${SPINNER[tick]} pr-watch #${w.prNumber} CI:${ci} ${review}`);
  if (ci !== w.lastCi) {
    if (ci === "fail" && !w.notifiedCiFail) {
      w.notifiedCiFail = true;
      $.ui.toast(`PR #${w.prNumber}: CI fail`, { timeoutMs: 10000 });
      await $.prompt.submit({
        text: `PR #${w.prNumber} の CI が fail した。gh pr checks ${w.prNumber} で原因を確認し、修正して push せよ。`,
      });
    }
    if (ci === "pass" && w.lastCi !== undefined) {
      $.ui.toast(`PR #${w.prNumber}: CI pass`);
    }
    w.lastCi = ci;
  }

  // 増分ではなく未解決スレッドの有無で判定する (監視開始前に到着したレビューも拾うため)
  if (!w.notifiedReview && copilotReviews > 0) {
    const home = await $.env.get("HOME");
    let unresolved = "?";
    if (home) {
      const t = await $.process.run([
        "bash",
        `${home}/.claude/skills/pr-review-fix/scripts/fetch_unresolved_threads.sh`,
        String(w.prNumber),
      ]);
      if (t.exitCode === 0) {
        unresolved = String(
          t.stdout.split("\n").filter((l) => l.trim()).length,
        );
      }
    }
    if (unresolved === "0") return;
    w.notifiedReview = true;
    $.ui.toast(
      `PR #${w.prNumber}: Copilot レビュー (未解決 ${unresolved} 件)`,
      {
        timeoutMs: 10000,
      },
    );
    await $.prompt.submit({
      text: `PR #${w.prNumber} に Copilot レビューの未解決スレッドが ${unresolved} 件ある。ship フロー中なら ship の手順に従い、pr-review-fix スキルで対応せよ。件数が ? (取得失敗) の場合は fetch_unresolved_threads.sh で確認してから判断すること。`,
    });
  }
}

// リロード時はタイマー破棄 + session.start 非再発火のため、任意のフックから遅延起動できるようにする
function ensurePoller($: EngineInterface): void {
  if (pollerStarted) return;
  pollerStarted = true;
  $.clock.every(5000, () => poll($));
}

export const register: Register = (on) => {
  on("session.start", ($, e, next) => {
    ensurePoller($);
    return next(e);
  });
  on("prompt.submit", ($, e, next) => {
    ensurePoller($);
    // タイマーの $ がリロード等で死んでいても、ターンごとに表示が更新されるようにする
    void poll($);
    return next(e);
  });
};
