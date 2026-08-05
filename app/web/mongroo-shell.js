(() => {
  const loading = document.getElementById('app-loading');
  const copy = document.getElementById('loading-copy');
  const track = document.getElementById('loading-track');
  const retry = document.getElementById('loading-retry');
  let completed = false;

  const restoreZoomableViewport = () => {
    const viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) return;
    const content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
    if (viewport.getAttribute('content') !== content) {
      viewport.setAttribute('content', content);
    }
  };
  const viewportObserver = new MutationObserver(restoreZoomableViewport);
  viewportObserver.observe(document.head, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['content'],
  });
  restoreZoomableViewport();

  performance.mark('mongroo-shell-ready');

  const showRecovery = () => {
    if (completed) return;
    copy.textContent = '불러오기가 조금 오래 걸리고 있어요. 네트워크를 확인해 주세요.';
    track.hidden = true;
    retry.hidden = false;
  };

  const watchdog = window.setTimeout(showRecovery, 20000);
  retry.addEventListener('click', () => window.location.reload());

  window.addEventListener(
    'flutter-first-frame',
    () => {
      completed = true;
      restoreZoomableViewport();
      window.setTimeout(() => viewportObserver.disconnect(), 1000);
      window.clearTimeout(watchdog);
      performance.mark('mongroo-flutter-first-frame');
      loading.classList.add('is-ready');
      const removalDelay = window.matchMedia('(prefers-reduced-motion: reduce)').matches
        ? 0
        : 220;
      window.setTimeout(() => loading.remove(), removalDelay);
    },
    { once: true },
  );

  window.addEventListener(
    'error',
    (event) => {
      if (event.target?.id === 'flutter-bootstrap') showRecovery();
    },
    { capture: true },
  );
})();
