import type { Register } from "claude-code";

// Manual (default) モードはフッターにラベルが出ない (modes が空) ことを判定に使う。
// SessionMode はモード切替のたびに再描画されるため、statusline のファイル経由と違い遅延なく反映される
export const register: Register = (on) => {
  on("ui.render", { component: "SessionMode" }, ($, e, next) => {
    if (e.props.modes.length > 0) return next(e);
    const { Text } = $.ui.resolve(e);
    return (
      <Text color="red" bold>
        MANUAL: 全操作を確認制にしています
      </Text>
    );
  });
};
