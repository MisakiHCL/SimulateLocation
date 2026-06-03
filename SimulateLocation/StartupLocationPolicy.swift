struct StartupLocationPolicy {
    private var hasRequestedCurrentLocation = false

    mutating func consumeShouldRequestCurrentLocation() -> Bool {
        guard !hasRequestedCurrentLocation else {
            return false
        }

        hasRequestedCurrentLocation = true
        return true
    }
}
