import type { EngineInterface, Register } from "claude-code";
import { type CiState, ciSummaryOf } from "./ci.ts";
import { countCopilotReviews, type Review, reviewSettled } from "./reviews.ts";
import {
  afterFailure,
  afterSuccess,
  due,
  forced,
  initialSchedule,
  observeLocal,
  park,
  type Schedule,
  slowDown,
} from "./schedule";
import {
  closedNotice,
  deferred,
  dueOthers,
  type Sub,
  subscribe,
  unsubscribe,
} from "./subscriptions";

type Threads = { total: number; resolved: number };

type Watched = {
  prNumber: number;
  prUrl?: string;
  lastCi?: CiState;
  notifiedReview: boolean;
  notifiedCiFail: boolean;
  // この PR でチェックを一度でも見たか。見た後の 0 件は push 直後の未登録として待つ
  sawChecks?: boolean;
  // reviewThreads クエリの節約用: 前回結果と、その時点の Copilot レビュー数
  threads?: Threads;
  threadsAtReviews?: number;
};

const watchedByNumber = new Map<number, Watched>();
// 今いるブランチの OPEN な PR。監視行に出すのはこの PR だけ
let currentNumber: number | undefined;
let pollerStarted = false;
// タイマーと prompt.submit から同時に走ると通知が多重化するため直列化する
let polling = false;
let schedule: Schedule = initialSchedule;
let tick = 0;
let hint: string | undefined;
// 部位別配色用。監視中のみ設定し、エラー表示等では undefined (hint を dim 単色で出す)
type Parts = {
  ci: string;
  ciColor?: string;
  review: string;
  reviewColor?: string;
  // CI 成功かつレビュー未解決 0 件。スピナーを止める判定に使う
  done: boolean;
};
let parts: Parts | undefined;

// 完了・要対応はポーリング待ちではなく人/モデルの対応待ちなので、回転させず固定記号にする
function staticGlyph(p: Parts | undefined): string | undefined {
  if (!p) return undefined;
  if (p.ciColor === "red" || p.reviewColor === "red") return "✗";
  if (p.done) return "✓";
  return undefined;
}

// 上段ドットのみのフレーム (⠋⠙…) は行の上に寄って見えるため、全 8 点を使う系列にする
const SPINNER = ["⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽", "⣾"];

function setHint(
  $: EngineInterface,
  text: string | undefined,
  next?: Parts,
): void {
  if (hint === text) return;
  hint = text;
  parts = next;
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

// /pr-watch の処理中に起こすと、そのコマンドが抱えるターンを待つ形になりエンジンに拒否されるので、コマンドを返した後へ回す
let inCommand = false;

async function wake($: EngineInterface, text: string): Promise<void> {
  if (inCommand) {
    $.clock.after(0, () => void $.prompt.submit({ text }));
    return;
  }
  await $.prompt.submit({ text });
}

async function refetch($: EngineInterface): Promise<void> {
  schedule = forced(schedule);
  await poll($);
}

type PrView = {
  number: number;
  state: string;
  url?: string;
  statusCheckRollup?: {
    state?: string;
    conclusion?: string;
    status?: string;
  }[];
  reviews?: Review[];
};

type ViewResult = { pr?: PrView; rateLimited: boolean };

// target 省略時は今いるブランチの PR、指定時はその URL の PR を取る
async function viewPr(
  $: EngineInterface,
  target?: string,
): Promise<ViewResult> {
  const argv = ["gh", "pr", "view"];
  if (target) argv.push(target);
  argv.push("--json", "number,state,url,statusCheckRollup,reviews");
  const r = await $.process.run(argv);
  const json = r.exitCode === 0 ? r.stdout.trim() : "";
  if (!json) return { rateLimited: /rate limit/i.test(r.stderr) };
  try {
    return { pr: JSON.parse(json) as PrView, rateLimited: false };
  } catch {
    return { rateLimited: false };
  }
}

async function loadSubs($: EngineInterface): Promise<Sub[]> {
  return ((await $.store.get(await subsKey($))) as Sub[] | undefined) ?? [];
}

async function saveSubs($: EngineInterface, subs: Sub[]): Promise<void> {
  await $.store.set(await subsKey($), subs);
}

// store はセッションをまたいで共有されるので、購読はセッションごとに分ける
async function subsKey($: EngineInterface): Promise<string> {
  return `subs:${await $.session.id()}`;
}

async function onClosed($: EngineInterface, pr: PrView): Promise<void> {
  const subs = await loadSubs($);
  if (!subs.some((s) => s.number === pr.number)) return;
  await saveSubs($, unsubscribe(subs, pr.number));
  watchedByNumber.delete(pr.number);
  const notice = closedNotice(pr.number, pr.state);
  if (notice) await wake($, notice);
}

async function pollOnce($: EngineInterface): Promise<void> {
  const run = async (argv: readonly string[]) => {
    const r = await $.process.run(argv);
    return r.exitCode === 0 ? r.stdout.trim() : undefined;
  };

  const branch = await run(["git", "rev-parse", "--abbrev-ref", "HEAD"]);
  const head = await run(["git", "rev-parse", "HEAD"]);
  const upstream = await run(["git", "rev-parse", "@{upstream}"]);
  schedule = observeLocal(schedule, [branch, head, upstream].join(" "));
  if (due(schedule, Date.now())) await pollCurrent($, run, branch);
  await pollOthers($);
}

async function pollCurrent(
  $: EngineInterface,
  run: (argv: readonly string[]) => Promise<string | undefined>,
  branch: string | undefined,
): Promise<void> {
  const defaultBranch = (
    (await run([
      "git",
      "symbolic-ref",
      "--short",
      "refs/remotes/origin/HEAD",
    ])) ?? ""
  ).replace(/^origin\//, "");
  if (!branch || branch === defaultBranch) {
    currentNumber = undefined;
    setHint($, undefined);
    return;
  }

  const { pr, rateLimited } = await viewPr($);
  if (!pr) {
    schedule = afterFailure(schedule, Date.now(), rateLimited);
    setHint(
      $,
      rateLimited
        ? `pr-watch 停止中 (GitHub API 上限、${Math.round(schedule.backoffMs / 60000)} 分後に再試行)`
        : `pr-watch 待機中 (gh 失敗、${Math.round(schedule.backoffMs / 1000)}s 後に再試行)`,
    );
    return;
  }
  schedule = afterSuccess(schedule, Date.now());
  if (pr.state !== "OPEN") {
    schedule = park(schedule);
    currentNumber = undefined;
    setHint($, undefined);
    await onClosed($, pr);
    return;
  }
  currentNumber = pr.number;
  if (pr.url)
    await saveSubs($, subscribe(await loadSubs($), pr.number, pr.url));
  await onOpen($, pr, true);
}

// 今いるブランチ以外の購読中の PR も、マージ・クローズ・CI・レビューを拾う
async function pollOthers($: EngineInterface): Promise<void> {
  let subs = await loadSubs($);
  const targets = dueOthers(subs, currentNumber, Date.now());
  if (targets.length === 0) return;
  for (const s of targets) {
    subs = deferred(subs, s.number, Date.now());
    const { pr } = await viewPr($, s.url);
    if (!pr) continue;
    if (pr.state !== "OPEN") {
      await saveSubs($, subs);
      await onClosed($, pr);
      subs = await loadSubs($);
      continue;
    }
    await onOpen($, pr, false);
  }
  await saveSubs($, subs);
}

async function onOpen(
  $: EngineInterface,
  pr: PrView,
  isCurrent: boolean,
): Promise<void> {
  const copilot = countCopilotReviews(pr.reviews ?? []);
  const copilotReviews = copilot.reviewed;
  const copilotUnable = copilot.unable;

  let w = watchedByNumber.get(pr.number);
  if (!w) {
    w = { prNumber: pr.number, notifiedReview: false, notifiedCiFail: false };
    watchedByNumber.set(pr.number, w);
  }
  w.prUrl = pr.url;

  const rollup = pr.statusCheckRollup ?? [];
  if (rollup.length > 0) w.sawChecks = true;
  const { state: ci, done, total } = ciSummaryOf(rollup, w.sawChecks ?? false);

  // レビュースレッドは isResolved のみの軽量クエリで全件/解決済みを数える。
  // 新しいレビューが来たか未解決が残っている時だけ再取得する (指摘 0 件・全解決なら止める)
  const needThreads =
    copilotReviews > 0 &&
    (w.threadsAtReviews !== copilotReviews ||
      (w.threads !== undefined && w.threads.total - w.threads.resolved > 0));
  let threads = w.threads;
  if (needThreads && pr.url) {
    const m = pr.url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\//);
    if (m) {
      const r = await $.process.run([
        "gh",
        "api",
        "graphql",
        "--paginate",
        "-F",
        `owner=${m[1]}`,
        "-F",
        `repo=${m[2]}`,
        "-F",
        `number=${w.prNumber}`,
        "-f",
        "query=query($owner:String!,$repo:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}nodes{isResolved}}}}}",
        "--jq",
        ".data.repository.pullRequest.reviewThreads.nodes[].isResolved",
      ]);
      if (r.exitCode === 0) {
        const flags = r.stdout.split("\n").filter((l) => l.trim() !== "");
        threads = {
          total: flags.length,
          resolved: flags.filter((f) => f.trim() === "true").length,
        };
        w.threads = threads;
        w.threadsAtReviews = copilotReviews;
      }
    }
  }

  const review = threads
    ? `レビュー ${threads.resolved}/${threads.total}`
    : w.notifiedReview
      ? "レビュー通知済"
      : copilotReviews > 0
        ? "レビュー到着"
        : copilotUnable > 0
          ? "レビュー不可"
          : "レビュー待ち";
  const ciLabel = total > 0 ? `CI:${ci} ${done}/${total}` : `CI:${ci}`;
  const ciColor =
    ci === "pass" || ci === "none"
      ? "green"
      : ci === "fail"
        ? "red"
        : ci === "pending"
          ? "cyan"
          : undefined;
  const reviewColor = !threads
    ? "cyan"
    : threads.total - threads.resolved > 0
      ? "red"
      : "green";
  const allDone =
    (ci === "pass" || ci === "none") &&
    reviewSettled(
      copilot,
      threads ? threads.total - threads.resolved : undefined,
    );
  if (isCurrent) {
    if (allDone) schedule = slowDown(schedule, Date.now());
    setHint($, `pr-watch #${w.prNumber} ${ciLabel} ${review}`, {
      ci: ciLabel,
      ciColor,
      review,
      reviewColor,
      done: allDone,
    });
  }

  // 全完了は一度だけ起こす。未完了に戻ったら (再 push 等) 次の完了も拾えるよう解除する
  const doneKey = `notified-done:${w.prNumber}`;
  if (!allDone) {
    if (await $.store.get(doneKey)) await $.store.set(doneKey, "");
  } else if (!(await $.store.get(doneKey))) {
    await $.store.set(doneKey, "1");
    await wake(
      $,
      `PR #${w.prNumber} の CI が全て完了し、Copilot レビューの未解決スレッドも無い。flow 中なら flow の手順に従い次のフェーズへ進め。`,
    );
  }

  if (ci !== w.lastCi) {
    // fail から抜けたら通知済みフラグを戻し、次の fail も拾えるようにする
    if (ci !== "fail") w.notifiedCiFail = false;
    if (ci === "fail" && !w.notifiedCiFail) {
      w.notifiedCiFail = true;
      await wake(
        $,
        `PR #${w.prNumber} の CI が fail した。gh pr checks ${w.prNumber} で原因を確認し、修正して push せよ。`,
      );
    }
    w.lastCi = ci;
  }

  // 増分ではなく未解決スレッドの有無で判定する (監視開始前に到着したレビューも拾うため)
  if (copilotReviews > 0) {
    const notifyKey = `notified-review:${w.prNumber}`;
    // 件数不明 (取得失敗) は "?" のままにして誤起床を防ぐ
    const unresolved = threads ? String(threads.total - threads.resolved) : "?";
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
    await wake(
      $,
      `PR #${w.prNumber} に Copilot レビューの未解決スレッドが ${unresolved} 件ある。flow 中なら flow の手順に従い、pr-review-fix スキルで対応せよ。件数が ? (取得失敗) の場合は fetch_unresolved_threads.sh で確認してから判断すること。`,
    );
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
    if (staticGlyph(parts)) return;
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
    inCommand = true;
    try {
      await refetch($);
    } finally {
      inCommand = false;
    }
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
    const { Box, Text, Button } = $.ui.resolve(e);
    const watched =
      currentNumber === undefined
        ? undefined
        : watchedByNumber.get(currentNumber);
    const url = watched?.prUrl;
    if (!parts || !watched) {
      return <Text dimColor>{`${SPINNER[tick]} ${hint}`}</Text>;
    }
    // 失敗 (赤) > 未完了 (シアン) > 両方完了 (緑) の優先で CI とレビューの色を合成する
    const colors = [parts.ciColor, parts.reviewColor];
    const spinnerColor = colors.includes("red")
      ? "red"
      : colors.includes("cyan")
        ? "cyan"
        : colors.every((c) => c === "green")
          ? "green"
          : undefined;
    // Button のラベルは単色のため、クリック対象は「pr-watch #番号」までにして残りを部位別の色で描く
    return (
      <Box>
        <Text color={spinnerColor} dimColor={!spinnerColor}>
          {`${staticGlyph(parts) ?? SPINNER[tick]} `}
        </Text>
        {url ? (
          <Button
            key="pr-watch-ci"
            label={`pr-watch #${watched.prNumber}`}
            plain
            dimColor
            onPress={() => void $.process.run(["open", `${url}/checks`])}
          />
        ) : (
          <Text dimColor>{`pr-watch #${watched.prNumber}`}</Text>
        )}
        <Text> </Text>
        <Text color={parts.ciColor} dimColor={!parts.ciColor}>
          {parts.ci}
        </Text>
        <Text> </Text>
        <Text color={parts.reviewColor} dimColor={!parts.reviewColor}>
          {parts.review}
        </Text>
        <Text> </Text>
        <Button
          key="pr-watch-refetch"
          label="↻"
          plain
          dimColor
          onPress={() => void refetch($)}
        />
      </Box>
    );
  });
};
