import Vapor
import Fluent

final class MeetingDateController: RouteCollection {
    func build(_ builder: RouteBuilder) throws {
        builder.versioned().auth() { build in
            build.post("/project", Project.parameter, "/dates", handler: addDatesToProject)
            build.post("/project", Project.parameter, "/date", handler: addDatetoProject)
            build.patch("/project", Project.parameter, "/date", MeetingDate.parameter, handler: pickDate)
            build.post("/vote", MeetingDate.parameter, handler: vote)
            build.patch("/project", Project.parameter, "/attend", handler: willAttend)
            build.patch("/project", Project.parameter, "/notAttend", handler: willNotAttend)
        }
    }

    //MARK: - POST /project/{project_id}/dates
    func addDatesToProject(_ req: Request) throws -> ResponseRepresentable {
        let user = try req.user()
        let project: Project = try req.parameters.next()
        
        guard try user.assertExists() == project.user_id else { throw Abort.notFound }
        guard let jsonArray = req.json?.array else { throw Abort.badRequest }
    
        for var jsonObject in jsonArray {
            try jsonObject.set("project_id", try project.assertExists())
            
            try MeetingDate(json: jsonObject).save()
        }
        
        return Response(status: .ok)
    }
    
    //MARK: - METHOD /project/{project_id}/date
    func addDatetoProject(_ req: Request) throws -> ResponseRepresentable {
        let user = try req.user()
        let project: Project = try req.parameters.next()
        
        guard try user.assertExists() == project.user_id else { throw Abort.notFound }
        guard var json = req.json else { throw Abort.badRequest }
        try json.set("project_id", try project.assertExists())
        try MeetingDate(json: json).save()

        return Response(status: .ok)
    }
    
    //MARK: - PATCH /project/{project_id}/date/{meeting_date_id}
    func pickDate(_ req: Request) throws -> ResponseRepresentable {
        let user = try req.user()
        let project: Project = try req.parameters.next()
        let meetingDate: MeetingDate = try req.parameters.next()
        
        guard try user.assertExists() == project.user_id else { throw Abort.notFound }
        
        project.meeting_date_id = meetingDate.id
        try project.save()
        
        let projectUserQuery = try ProjectUser
            .makeQuery()
            .filter(ProjectUser.Field.user_id, try user.assertExists())
            .filter(ProjectUser.Field.project_id, try project.assertExists())
        
        if let projectUser = try projectUserQuery.first() {
            projectUser.attending = true
            try projectUser.save()
        } else {
            //somehow the ProjectUser didn't get created, create it here
            try ProjectUser(
                user_id: try user.assertExists(),
                project_id: try project.assertExists(),
                attending: true,
                accepted: true
                ).save()
        }
        
        return Response(status: .ok)
    }
    
    //MARK: - POST /vote/{meeting_date_id}
    func vote(_ req: Request) throws -> ResponseRepresentable {
        let user = try req.user()
        let meetingDate: MeetingDate = try req.parameters.next()
        
        guard let project = try meetingDate.project.get() else { throw Abort.badRequest }
        guard try user.userCanAccess(project: project) else { throw Abort.notFound }
        
        //delete all current votes
        let allMeetingDatesForProject = try project.meetingDates.all().flatMap { $0.id }
        for meetingId in allMeetingDatesForProject {
            try Pivot<User, MeetingDate>.makeQuery()
                .filter("user_id", user.id)
                .filter("meeting_date_id", meetingId).delete()
        }
        
        let pivot = try Pivot<User, MeetingDate>(user, meetingDate)
        try pivot.save()
        
        var responseJSON = JSON()
        try responseJSON.set("meeting_date_id", meetingDate.id)
        try responseJSON.set("votes", try meetingDate.votes())
        
        return responseJSON
    }
    
    //MARK: - PATCH /project/{project_id}/attend
    func willAttend(_ req: Request) throws -> ResponseRepresentable {
        let project: Project = try req.parameters.next()
        let user = try req.user()
        
        guard try user.userCanAccess(project: project) else { throw Abort.badRequest }
        guard let projectUser = try ProjectUser.makeQuery().filter(ProjectUser.Field.user_id, user.id).filter(ProjectUser.Field.project_id, project.id).first() else { throw Abort.badRequest }
        
        projectUser.attending = true
        try projectUser.save()
        
        return Response(status: .ok)
    }
    
    //MARK: - PATCH /project/{project_id}/notAttend
    func willNotAttend(_ req: Request) throws -> ResponseRepresentable {
        let project: Project = try req.parameters.next()
        let user = try req.user()
        
        guard try user.userCanAccess(project: project) else { throw Abort.badRequest }
        guard let projectUser = try ProjectUser.makeQuery().filter(ProjectUser.Field.user_id, user.id).filter(ProjectUser.Field.project_id, project.id).first() else { throw Abort.badRequest }
        
        projectUser.attending = false
        try projectUser.save()
        
        return Response(status: .ok)
    }
}

//MARK: - EmptyInitializable
extension MeetingDateController: EmptyInitializable { }
