import type { EngineInterface, Register } from "claude-code";

type CiState = "pass" | "fail" | "pending" | "none";

type Watched = {
  prNumber: number;
  prUrl?: string;
  lastCi?: CiState;
  notifiedReview: boolean;
  notifiedCiFail: boolean;
};

let watched: Watched | undefined;
let pollerStarted = false;
// タイマーと prompt.submit から同時に走ると通知が多重化するため直列化する
let polling = false;
// gh pr view は GraphQL で 1 回あたりの消費が大きく、15 秒 × 複数セッションで上限 (5000/時) を実際に枯渇させたため 60 秒にする
const MIN_GH_INTERVAL_MS = 60000;
const MAX_BACKOFF_MS = 900000;
const RATE_LIMIT_BACKOFF_MS = 600000;
let nextGhAt = 0;
let backoffMs = 0;
let tick = 0;
let hint: string | undefined;

// 上段ドットのみのフレーム (⠋⠙…) は行の上に寄って見えるため、全 8 点を使う系列にする
const SPINNER = ["⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽", "⣾"];

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

function setHint($: EngineInterface, text: string | undefined): void {
  if (hint === text) return;
  hint = text;
  $.ui.invalidate("ui.render");
}

async function poll($: EngineInterface): Promise<void> {
  if (polling) return;
  polling = true;
  try {
    await pollOnce($);
  } finally {
    polling = false;
  }
}

async function pollOnce($: EngineInterface): Promise<void> {
  const now = Date.now();
  if (now < nextGhAt) return;
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
    watched = undefined;
    setHint($, undefined);
    return;
  }

  const view = await $.process.run([
    "gh",
    "pr",
    "view",
    "--json",
    "number,state,url,statusCheckRollup,reviews",
  ]);
  const json = view.exitCode === 0 ? view.stdout.trim() : undefined;
  if (!json) {
    // 上限超過は分単位で回復しないため、通常の失敗より強く間隔を空ける
    if (/rate limit/i.test(view.stderr)) {
      backoffMs = RATE_LIMIT_BACKOFF_MS;
      nextGhAt = Date.now() + backoffMs;
      setHint($, "pr-watch 停止中 (GitHub API 上限、10 分後に再試行)");
      return;
    }
    // 失敗の多くは API 上限。間隔を広げて枯渇を助長しない
    backoffMs = Math.min(
      backoffMs ? backoffMs * 2 : MIN_GH_INTERVAL_MS,
      MAX_BACKOFF_MS,
    );
    nextGhAt = Date.now() + backoffMs;
    setHint(
      $,
      `pr-watch 待機中 (gh 失敗、${Math.round(backoffMs / 1000)}s 後に再試行)`,
    );
    return;
  }
  backoffMs = 0;
  nextGhAt = Date.now() + MIN_GH_INTERVAL_MS;
  let pr: {
    number: number;
    state: string;
    url?: string;
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
    watched = undefined;
    setHint($, undefined);
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
  w.prUrl = pr.url;

  const ci = ciStateOf(pr.statusCheckRollup ?? []);
  const review = w.notifiedReview
    ? "レビュー通知済"
    : copilotReviews > 0
      ? "レビュー到着"
      : "レビュー待ち";
  setHint($, `pr-watch #${w.prNumber} CI:${ci} ${review}`);

  if (ci !== w.lastCi) {
    // fail から抜けたら通知済みフラグを戻し、次の fail も拾えるようにする
    if (ci !== "fail") w.notifiedCiFail = false;
    if (ci === "fail" && !w.notifiedCiFail) {
      w.notifiedCiFail = true;
      await $.prompt.submit({
        text: `PR #${w.prNumber} の CI が fail した。gh pr checks ${w.prNumber} で原因を確認し、修正して push せよ。`,
      });
    }
    w.lastCi = ci;
  }

  // 増分ではなく未解決スレッドの有無で判定する (監視開始前に到着したレビューも拾うため)
  if (copilotReviews > 0) {
    const notifyKey = `notified-review:${w.prNumber}`;
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
    if (unresolved === "0") {
      await $.store.set(notifyKey, "0");
      return;
    }
    // 件数不明では起こさない (API 上限等の一時失敗で誤起床しないため)
    if (unresolved === "?") return;
    // モジュールのリロードで通知済みフラグが消えないよう store に持たせる
    if ((await $.store.get(notifyKey)) === unresolved) return;
    await $.store.set(notifyKey, unresolved);
    w.notifiedReview = true;
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
  // 回転グリフはアニメーションなので gh ポーリングとは別の短周期で回す
  $.clock.every(120, () => {
    if (!hint) return;
    tick = (tick + 1) % SPINNER.length;
    $.ui.invalidate("ui.render");
  });
}

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    await $.command.register({
      name: "pr-watch",
      description: "pr-watch の監視状態を今すぐ更新して表示する",
    });
    ensurePoller($);
    return next(e);
  });

  on("command.run", { command: "pr-watch" }, async ($, _e, _next) => {
    nextGhAt = 0;
    await poll($);
    return {
      text: hint ?? "pr-watch: 監視対象なし (PR のあるブランチにいない)",
    };
  });

  on("prompt.submit", ($, e, next) => {
    ensurePoller($);
    void poll($);
    return next(e);
  });

  // 1 行で足りるので、$.ui.status (黄色) や Pane ではなくプロンプト直上の帯に描く
  on("ui.render", { component: "AbovePrompt" }, ($, e, next) => {
    if (!hint) return next(e);
    const { Text, Button } = $.ui.resolve(e);
    const failing = watched?.lastCi === "fail";
    const line = `${SPINNER[tick]} ${hint}`;
    const url = watched?.prUrl;
    if (url) {
      // Button に色は付けられないため fail 時は非 dim で目立たせる
      return (
        <Button
          key="pr-watch-ci"
          label={line}
          plain
          dimColor={!failing}
          onPress={() => void $.process.run(["open", `${url}/checks`])}
        />
      );
    }
    return failing ? (
      <Text color="red">{line}</Text>
    ) : (
      <Text dimColor>{line}</Text>
    );
  });
};
