@_exported import Vapor

extension Droplet {
    public func setup() throws {
        //Register routes
        try routes()
    }
}