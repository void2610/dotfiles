import type { EngineInterface } from "claude-code";

// 検証器は $ を import 越しに追えないため、$ の呼び出しは index.ts に閉じ、機能ファイルへはこの型の関数を渡す
export type Run = EngineInterface["process"]["run"];
export type ReadFile = (path: string) => Promise<string>;
