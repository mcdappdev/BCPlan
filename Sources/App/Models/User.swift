import Vapor
import FluentProvider
import AuthProvider
import Validation

final class User: Model {
    var storage = Storage()
    
    var name: String
    var email: String
    var password: String
    var admin: Bool
    
    var adminProjects: Children<User, Project> {
        return children()
    }
    
    var projectInvitations: Siblings<User, Project, ProjectUser> {
        return siblings()
    }
    
    var projectUsers: Children<User, ProjectUser> {
        return children()
    }
    
    init(name: String, email: String, password: String, admin: Bool = false) throws {
        self.name = name
        self.email = try email.tested(by: EmailValidator())
        self.password = password
        self.admin = admin
    }
    
    init(row: Row) throws {
        name = try row.get(Field.name)
        
        let email: String = try row.get(Field.email)
        self.email = try email.tested(by: EmailValidator())
        
        password = try row.get(Field.password)
        admin = try row.get(Field.admin) ?? false
    }
    
    func makeRow() throws -> Row {
        var row = Row()
        
        try row.set(Field.name, name)
        try row.set(Field.email, email)
        try row.set(Field.password, password)
        try row.set(Field.admin, admin)
        
        return row
    }
    
    init(json: JSON) throws {
        name = try json.get(Field.name)
        
        let email: String = try json.get(Field.email)
        self.email = try email.tested(by: EmailValidator())
        
        password = try json.get(Field.password)
        admin = try json.get(Field.admin) ?? false
    }
    
    //these are accepted projects that are not included in the admin projects
    func acceptedProjects() throws -> [Project] {
        return try projectInvitations
            .makeQuery()
            .filter(ProjectUser.self, ProjectUser.Field.accepted.rawValue, true)
            .filter(Project.self, Project.Field.user_id.rawValue, .notEquals, id)
            .sort(ProjectUser.Field.id.rawValue, .descending)
            .all()
    }
    
    func pendingProjects() throws -> [Project] {
        return try projectInvitations
            .makeQuery()
            .filter(ProjectUser.self, ProjectUser.Field.accepted.rawValue, false)
            .filter(Project.self, Project.Field.user_id.rawValue, .notEquals, id)
            .sort(ProjectUser.Field.id.rawValue, .descending)
            .all()
    }
    
    func attendingProjects() throws -> [Project] {
        return try projectInvitations.makeQuery().filter(ProjectUser.self, ProjectUser.Field.attending.rawValue, true).all()
    }

    //this method could be made easier to read, but it's been left as is because
    //it currently won't execute all three queries if the first is true
    func userCanAccess(project: Project) throws -> Bool {
        guard let projectId = project.id else { return false }
        
        //first check to see if they're an admin
        if try adminProjects.makeQuery().filter(Project.Field.id, project.id).count() != 0 {
            return true
        } else if (try acceptedProjects().flatMap { $0.id }).contains(projectId) {
            //it's an accepted project
            return true
        } else if (try pendingProjects().flatMap { $0.id }).contains(projectId) {
            //it's a pending project
            return true
        }
        
        return false
    }
}

//MARK: - JSONConvertible
extension User: JSONConvertible {
    func makeJSON() throws -> JSON {
        var json = JSON()
        
        try json.set(Field.id, id)
        try json.set(Field.name, name)
        try json.set(Field.email, email)
        try json.set(Field.admin, admin)
        try json.set(User.createdAtKey, createdAt)
        try json.set(User.updatedAtKey, updatedAt)
        try json.set("token", try token()?.token)
        
        return json
    }
}

//MARK: - Preparation
extension User: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(self, closure: { builder in
            builder.id()
            builder.string(Field.name)
            builder.string(Field.email, unique: true)
            builder.string(Field.password)
            builder.bool(Field.admin)
        })
    }
    
    static func revert(_ database: Database) throws {
        
    }
}

//MARK: - token()
extension User {
    func token() throws -> Token? {
        return try children(type: Token.self, foreignIdKey: "user_id").first()
    }
}

//MARK: - TokenAuthenticatable
extension User: TokenAuthenticatable {
    public typealias TokenType = Token
}

//MARK: - Request User Method
extension Request {
    func user() throws -> User {
        return try auth.assertAuthenticated()
    }
}

//MARK: - SessionPersistable
extension User: SessionPersistable { }

//MARK: - Timestampable
extension User: Timestampable { }

//MARK: - UserContext
struct UserContext: Context {
    var token: String
}

//MARK: - Authenticate/UnAuthenticate
extension User {
    func authenticate(req: Request) throws {
        try req.auth.authenticate(self, persist: true)
        try setSession(req: req)
    }
    
    private func setSession(req: Request) throws {
        try req.assertSession().data["user"] = self.makeJSON().makeNode(in: nil)
    }
    
    func unauthenticate(req: Request) throws {
        try req.auth.unauthenticate()
        try req.assertSession().destroy()
    }
}

//MARK: - Field
extension User {
    enum Field: String {
        case id
        case name
        case email
        case password
        case admin
    }
}
