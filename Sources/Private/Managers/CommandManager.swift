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
    
    func registerCommands() {
        
    }
    
    func getCommand(
        name: String,
        type: ApplicationCommand.CommandType = .slashCommand,
        scope: BotCommand.Scope = .global
    ) -> BotCommand? {
        commands.first { $0.name == name &&
            $0.type == type &&
            $0.scope == scope }
    }
}
