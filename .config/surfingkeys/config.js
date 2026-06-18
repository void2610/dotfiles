// Surfingkeys 設定ファイル
// 設定画面の "Load settings from" にこのファイルを置いた URL を指定 (/Users/<UserName>/dotfiles/.config/surfingkeys/config.js)

const { Hints, Visual, Front, Normal, RUNTIME, mapkey, unmap, imap, imapkey, map, vmap, cmap, addSearchAlias } = api;

// =====================================================================
// Insert モード
// =====================================================================
// jj で input/textarea からフォーカスを外して Normal モードへ戻る
// imap('jj', ...) だと最初の j がバッファされ続けて入力できないため、
// keydown を直接拾って 300ms 以内の連打を検出する
(() => {
  const THRESHOLD_MS = 300;
  let lastJAt = 0;
  let lastJTarget = null;

  window.addEventListener('keydown', (e) => {
    if (e.key !== 'j' || e.metaKey || e.ctrlKey || e.altKey) {
      lastJAt = 0;
      return;
    }
    const t = e.target;
    const editable = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
    if (!editable) return;

    const now = Date.now();
    if (lastJTarget === t && now - lastJAt < THRESHOLD_MS) {
      e.preventDefault();
      e.stopPropagation();
      // 1 つ目の j を消す
      if (t.isContentEditable) {
        document.execCommand('delete');
      } else {
        const v = t.value;
        const s = t.selectionStart;
        if (typeof s === 'number' && s > 0 && v[s - 1] === 'j') {
          t.value = v.slice(0, s - 1) + v.slice(s);
          t.selectionStart = t.selectionEnd = s - 1;
          t.dispatchEvent(new Event('input', { bubbles: true }));
        }
      }
      t.blur();
      lastJAt = 0;
      lastJTarget = null;
    } else {
      lastJAt = now;
      lastJTarget = t;
    }
  }, true);
})();

// =====================================================================
// 基本操作
// =====================================================================
// スクロール
map('J', 'd');
map('K', 'u');
map('H', 'S'); // 戻る
map('L', 'D'); // 進む

// タブ操作
map('t', 'on'); // 新規タブ
map('x', 'x');  // 現在タブを閉じる
map('X', 'X');  // 直前に閉じたタブを復元

// =====================================================================
// 検索エンジン
// =====================================================================
// 使い方: `o` で omnibar を開いてエイリアス + space + クエリ (例: `g claude`)
// addSearchAlias(alias, prompt, search_url, suggestion_url?, parse_callback?)
addSearchAlias(
  'g',
  'google',
  'https://www.google.com/search?q=',
  's',
  'https://www.google.com/complete/search?client=chrome&q=',
  (response) => JSON.parse(response.text)[1],
);

addSearchAlias(
  'y',
  'youtube',
  'https://www.youtube.com/results?search_query=',
  's',
  'https://suggestqueries.google.com/complete/search?client=youtube&ds=yt&q=',
  (response) => {
    const text = response.text.replace(/^[^(]*\(/, '').replace(/\)$/, '');
    return JSON.parse(text)[1].map((item) => item[0]);
  },
);

addSearchAlias(
  'h',
  'github',
  'https://github.com/search?q=',
);

addSearchAlias(
  'c',
  'claude',
  'https://claude.ai/new?q=',
);

// =====================================================================
// その他のカスタマイズ
// =====================================================================
// クリック対象のヒント表示文字 (ホームポジション優先)
settings.hintCharacters = 'asdfghjklqwertyuiopzxcvbnm';

// スムーススクロール
settings.smoothScroll = true;

// 検索結果のハイライト色
Visual.style('marks', 'background-color: #ffff00aa;');
Visual.style('cursor', 'background-color: #00d4ffaa;');
