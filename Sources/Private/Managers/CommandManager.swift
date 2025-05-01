//
//  CommandManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

actor CommandManager {
    
    private weak var restManager: RESTManager?
    private var commands: [BotCommand]
    
    init(restManager: RESTManager) {
        commands = []
        self.restManager = restManager
    }
    
    func addCommands(_ commands: [BotCommand]) {
        for command in commands {
            self.commands.append(command)
        }
    }
    
    func registerCommands(appID: Snowflake) async throws {
        let globals = commands.filter {
            if case .global = $0.scope {
                return true
            } else {
                return false
            }
        }
        try await restManager?.registerGlobalCommands(appID: appID, globals)
    }
    
    func getCommand(
        name: String,
        type: ApplicationCommand.CommandType = .slashCommand,
        scope: BotCommand.Scope
    ) -> BotCommand? {
        commands.first { command in
            guard command.name == name,
                  command.type == type else {
                return false
            }
            switch (command.scope, scope) {
            case let (.global(candidateIntegrationTypes, candidateContexts),
                      .global(requestedIntegrationTypes, requestedContexts)):
                return Set(requestedIntegrationTypes).isSubset(of: Set(candidateIntegrationTypes))
                    && Set(requestedContexts).isSubset(of: Set(candidateContexts))
            default:
                return command.scope == scope
            }
        }
    }
}
