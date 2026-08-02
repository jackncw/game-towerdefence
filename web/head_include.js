/*
 * 網頁版嘅 iOS 防線。呢個檔會俾 tools/apply_head_include.py 壓成一行,寫入
 * export_presets.cfg 嘅 html/head_include —— 即係話呢度先係原始碼,.cfg 入面
 * 嗰行係產物。改嘅時候改呢度,跟住行:
 *
 *     python tools/apply_head_include.py
 *
 * 點解要喺 JS 度做而唔係 GDScript:呢三件事全部喺 Godot 有機會行任何一句
 * 腳本之前(或者之後已經冇得行)就要成立 ——
 *
 *   1. devicePixelRatio 上限。Godot 嘅 canvasResizePolicy=2 會將 canvas backing
 *      store 設成 CSS 尺寸 x devicePixelRatio。iPhone 嘅 DPR 係 3,即係一個
 *      393x852 嘅視窗要一塊 1179x2556 = 3.0M pixel 嘅畫布;色彩 + 深度兩塊
 *      buffer 就係 24MB,再加 Godot 自己嘅 render target。封頂 2 之下同一部機
 *      係 1.34M pixel(-55%)。pixel art 用 NEAREST 放大,2x 同 3x 喺視覺上
 *      分唔出 —— 呢個係一個純粹嘅記憶體折讓。
 *      一定要喺 index.js 行之前改,所以呢段唔可以搬入 GDScript。
 *
 *   2. WebGL context lost。系統回收咗顯示記憶體之後,Godot 由嗰一刻起乜都畫
 *      唔到 —— 包括一句「我死咗」。所以呢個訊息一定要係頁面自己嘅 DOM。
 *
 *   3. visibilitychange / pagehide。切走嗰陣要暫停 + 收聲。JS 收到事件之後
 *      叫 window.__tfVisibility(hidden),嗰個 callback 由 Web.gd 掛上去。
 *      Godot 未起身嘅時候就記住最後一個狀態,等佢掛好即刻補返一次。
 */
(function () {
	var MAX_DPR = 2;
	var real = window.devicePixelRatio || 1;
	if (real > MAX_DPR) {
		try {
			Object.defineProperty(window, 'devicePixelRatio', {
				get: function () { return MAX_DPR; },
				configurable: true
			});
		} catch (e) { /* 改唔到就照舊,總好過喺呢度掟錯 */ }
	}
	window.__tfDpr = { real: real, capped: Math.min(real, MAX_DPR) };

	var zh = String(navigator.language || '').toLowerCase().indexOf('zh') === 0;

	/* --- 生命週期 ---------------------------------------------------------- */
	var pendingHidden = null;
	function tell(hidden) {
		if (typeof window.__tfVisibility === 'function') {
			pendingHidden = null;
			try { window.__tfVisibility(hidden); } catch (e) { /* 引擎已經走咗 */ }
		} else {
			pendingHidden = hidden;
		}
	}
	/* Web.gd 掛好 callback 之後叫呢個,補返佢錯過嗰次。 */
	window.__tfFlushVisibility = function () {
		if (pendingHidden !== null) { tell(pendingHidden); }
	};
	document.addEventListener('visibilitychange', function () {
		tell(!!document.hidden);
	});
	window.addEventListener('pagehide', function () { tell(true); });
	window.addEventListener('pageshow', function () { tell(false); });

	/* --- WebGL context lost ------------------------------------------------ */
	function showLostOverlay() {
		if (document.getElementById('tf-lost')) { return; }
		var box = document.createElement('div');
		box.id = 'tf-lost';
		box.setAttribute('style', 'position:fixed;inset:0;z-index:9999;display:flex;'
			+ 'flex-direction:column;align-items:center;justify-content:center;'
			/* 字型只寫 system-ui / -apple-system:iOS 喺中文地區會自己揀 PingFang,
			   而點名寫 font family 就要雙引號,而雙引號入唔到 .cfg 嗰行。 */
			+ 'background:#1c1611;color:#f7edd4;text-align:center;padding:2rem;'
			+ 'font-family:system-ui,-apple-system,sans-serif');
		var msg = document.createElement('div');
		msg.setAttribute('style', 'font-size:1.1rem;line-height:1.6;max-width:26rem');
		msg.textContent = zh
			? '畫面資源被系統回收,遊戲要重新載入。你嘅進度已經儲存。'
			: 'The system reclaimed the graphics memory. The game has to reload. Your progress is saved.';
		var btn = document.createElement('button');
		btn.textContent = zh ? '重新載入' : 'Reload';
		btn.setAttribute('style', 'margin-top:1.5rem;padding:0.9rem 2.4rem;font-size:1.1rem;'
			+ 'border:0;border-radius:0.6rem;background:#ffd147;color:#472e0d;font-weight:600');
		btn.addEventListener('click', function () { window.location.reload(); });
		box.appendChild(msg);
		box.appendChild(btn);
		document.body.appendChild(box);
	}
	function watchCanvas() {
		var c = document.getElementById('canvas');
		if (!c) { return false; }
		c.addEventListener('webglcontextlost', function (ev) {
			ev.preventDefault();
			showLostOverlay();
		}, false);
		return true;
	}
	if (!watchCanvas()) {
		document.addEventListener('DOMContentLoaded', watchCanvas);
	}
})();
