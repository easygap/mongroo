{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // 빌드에 포함된 렌더러를 써서 첫 실행을 외부 CDN 상태에서 분리한다.
    canvasKitBaseUrl: 'canvaskit/',
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
