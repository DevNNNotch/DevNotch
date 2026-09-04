import Foundation

let router = LocalAPIRouter(
    accessToken: "smoke-test-token",
    usageStore: UsageStore(),
    eventStore: EventStore()
)
let server = LocalAPIServer(router: router)
try server.start(port: 54732)
print("READY")
fflush(stdout)
Thread.sleep(forTimeInterval: 8)
server.stop()
