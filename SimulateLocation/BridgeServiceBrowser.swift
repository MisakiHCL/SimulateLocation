import Foundation

private enum BridgeDiscoveryConstants {
    static let serviceType = "_location-gpx._tcp."
    static let domain = "local."
    static let resolveTimeout: TimeInterval = 5
}

final class BridgeServiceBrowser: NSObject, ObservableObject {
    @Published private(set) var endpoint: BridgeEndpoint?
    @Published private(set) var isSearching = false

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []

    override init() {
        super.init()
        browser.delegate = self
        start()
    }

    deinit {
        browser.stop()
        services.forEach { service in
            service.stop()
            service.delegate = nil
        }
    }

    func restart() {
        endpoint = nil
        services.removeAll()
        browser.stop()
        start()
    }

    private func start() {
        isSearching = true
        browser.searchForServices(
            ofType: BridgeDiscoveryConstants.serviceType,
            inDomain: BridgeDiscoveryConstants.domain
        )
    }
}

extension BridgeServiceBrowser: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async {
            self.isSearching = true
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: BridgeDiscoveryConstants.resolveTimeout)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        services.removeAll { $0 == service }
        if endpoint?.port == service.port {
            DispatchQueue.main.async {
                self.endpoint = nil
            }
        }
    }
}

extension BridgeServiceBrowser: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, sender.port > 0 else {
            return
        }

        let resolvedEndpoint = BridgeEndpoint(host: host, port: sender.port)
        DispatchQueue.main.async {
            self.endpoint = resolvedEndpoint
            self.isSearching = false
        }
    }
}
