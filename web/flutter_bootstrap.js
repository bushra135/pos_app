{{flutter_js}}
{{flutter_build_config}}

// Each build has a distinct entrypoint URL so mobile browsers fetch updates.
// This changes app assets only; saved receipts and account data stay intact.
const release = {{flutter_service_worker_version}};
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?release=' + encodeURIComponent(release);
  }
}
_flutter.loader.load();
