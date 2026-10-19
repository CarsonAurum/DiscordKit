# API Reference

Browse the public types and operations provided by DiscordCommandDSL.

## Topics

### Argument Values

- ``DiscordCommandDSL/ArgumentValue``
- ``DiscordCommandDSL/ArgumentValueError``
- ``DiscordCommandDSL/AttachmentReference``
- ``DiscordCommandDSL/ChannelReference``
- ``DiscordCommandDSL/MentionableID``
- ``DiscordCommandDSL/MentionableReference``
- ``DiscordCommandDSL/MentionableTag``
- ``DiscordCommandDSL/RoleReference``
- ``DiscordCommandDSL/StringArgumentChoice``
- ``DiscordCommandDSL/UserReference``

### Autocomplete Commands

- ``DiscordCommandDSL/AutocompleteChoice``
- ``DiscordCommandDSL/AutocompleteCommand``
- ``DiscordCommandDSL/AutocompleteCommandHandler``
- ``DiscordCommandDSL/AutocompleteInput``
- ``DiscordCommandDSL/AutocompleteResponse``
- ``DiscordCommandDSL/AutocompleteValue``

### Command Application

- ``DiscordCommandDSL/CommandApplication``
- ``DiscordCommandDSL/CommandApplicationError``

### Command Arguments

- ``DiscordCommandDSL/AnyArgumentOption``
- ``DiscordCommandDSL/ArgumentDecoder``
- ``DiscordCommandDSL/ArgumentDefault``
- ``DiscordCommandDSL/ArgumentDiagnostic``
- ``DiscordCommandDSL/ArgumentOption``
- ``DiscordCommandDSL/CommandArguments``
- ``DiscordCommandDSL/CommandArgumentSchema``
- ``DiscordCommandDSL/UnknownArgumentPolicy``

### Command Compilation

- ``DiscordCommandDSL/CommandCompilation``
- ``DiscordCommandDSL/CommandCompilationDiagnostic``
- ``DiscordCommandDSL/CommandContribution``
- ``DiscordCommandDSL/CommandFamily``
- ``DiscordCommandDSL/CommandFamilyContribution``
- ``DiscordCommandDSL/CompiledCommands``
- ``DiscordCommandDSL/ExistingCommandFamily``

### Command Context

- ``DiscordCommandDSL/CommandContext``
- ``DiscordCommandDSL/DeferredCommandContext``

### Command Families

- ``DiscordCommandDSL/ComponentCommand``
- ``DiscordCommandDSL/ComponentHandler``
- ``DiscordCommandDSL/ComponentInput``
- ``DiscordCommandDSL/ContextMenuCommandMetadata``
- ``DiscordCommandDSL/DeferredComponentHandler``
- ``DiscordCommandDSL/DeferredInteractionResponseMode``
- ``DiscordCommandDSL/DeferredMessageCommandHandler``
- ``DiscordCommandDSL/DeferredModalHandler``
- ``DiscordCommandDSL/DeferredUserCommandHandler``
- ``DiscordCommandDSL/ManualComponentHandler``
- ``DiscordCommandDSL/ManualMessageCommandHandler``
- ``DiscordCommandDSL/ManualModalHandler``
- ``DiscordCommandDSL/ManualUserCommandHandler``
- ``DiscordCommandDSL/MessageCommand``
- ``DiscordCommandDSL/MessageCommandHandler``
- ``DiscordCommandDSL/MessageCommandTarget``
- ``DiscordCommandDSL/ModalCommand``
- ``DiscordCommandDSL/ModalHandler``
- ``DiscordCommandDSL/UserCommand``
- ``DiscordCommandDSL/UserCommandHandler``

### Command Handlers

- ``DiscordCommandDSL/DeferredSlashCommandHandler``
- ``DiscordCommandDSL/ExistingSlashCommand``
- ``DiscordCommandDSL/ManualSlashCommandHandler``
- ``DiscordCommandDSL/ModalSlashCommandHandler``
- ``DiscordCommandDSL/SlashCommand``
- ``DiscordCommandDSL/SlashCommandHandler``
- ``DiscordCommandDSL/SlashCommandMetadata``

### Command Policies

- ``DiscordCommandDSL/CommandConcurrencyAuthority``
- ``DiscordCommandDSL/CommandConcurrencyLimit``
- ``DiscordCommandDSL/CommandPolicies``
- ``DiscordCommandDSL/CommandPolicy``
- ``DiscordCommandDSL/CommandPolicyError``
- ``DiscordCommandDSL/CommandRejectionResponse``

### Command Responses

- ``DiscordCommandDSL/CommandResponseVisibility``
- ``DiscordCommandDSL/DeferredMessageResponse``
- ``DiscordCommandDSL/MessageResponse``

### Component Builder

- ``DiscordCommandDSL/Component``
- ``DiscordCommandDSL/ComponentBuilder``
- ``DiscordCommandDSL/ComponentButtonStyle``
- ``DiscordCommandDSL/ComponentList``
- ``DiscordCommandDSL/ComponentSelectKind``
- ``DiscordCommandDSL/MessageComponentMode``

### Extensions to standard library types

- ``DiscordCommandDSL/Swift``
- ``DiscordCommandDSL/Swift/Bool``
- ``DiscordCommandDSL/Swift/Double``
- ``DiscordCommandDSL/Swift/Int``
- ``DiscordCommandDSL/Swift/Int64``
- ``DiscordCommandDSL/Swift/Optional``
- ``DiscordCommandDSL/Swift/String``
- ``DiscordCommandDSL/Swift/Bool/argumentValue``
- ``DiscordCommandDSL/Swift/Bool/decodeArgument(_:resolved:)``
- ``DiscordCommandDSL/Swift/Bool/decodeModalInput(_:)``
- ``DiscordCommandDSL/Swift/Bool/modalComponentTypes``
- ``DiscordCommandDSL/Swift/Bool/optionType``
- ``DiscordCommandDSL/Swift/Double/argumentValue``
- ``DiscordCommandDSL/Swift/Double/decodeArgument(_:resolved:)``
- ``DiscordCommandDSL/Swift/Double/optionType``
- ``DiscordCommandDSL/Swift/Int/argumentValue``
- ``DiscordCommandDSL/Swift/Int/decodeArgument(_:resolved:)``
- ``DiscordCommandDSL/Swift/Int/optionType``
- ``DiscordCommandDSL/Swift/Int64/argumentValue``
- ``DiscordCommandDSL/Swift/Int64/decodeArgument(_:resolved:)``
- ``DiscordCommandDSL/Swift/Int64/optionType``
- ``DiscordCommandDSL/Swift/Optional/acceptsMissingModalInput``
- ``DiscordCommandDSL/Swift/Optional/argumentValue``
- ``DiscordCommandDSL/Swift/Optional/choices``
- ``DiscordCommandDSL/Swift/Optional/decodeArgument(_:resolved:)``
- ``DiscordCommandDSL/Swift/Optional/decodeModalInput(_:)``
- ``DiscordCommandDSL/Swift/Optional/isOptional``
- ``DiscordCommandDSL/Swift/Optional/modalComponentTypes``
- ``DiscordCommandDSL/Swift/Optional/optionType``
- ``DiscordCommandDSL/Swift/String/argumentValue``
- ``DiscordCommandDSL/Swift/String/decodeArgument(_:resolved:)``
- ``DiscordCommandDSL/Swift/String/decodeModalInput(_:)``
- ``DiscordCommandDSL/Swift/String/modalComponentTypes``
- ``DiscordCommandDSL/Swift/String/optionType``

### Family Responses

- ``DiscordCommandDSL/CommandInitialResponse``
- ``DiscordCommandDSL/ComponentInitialResponse``
- ``DiscordCommandDSL/ModalInitialResponse``
- ``DiscordCommandDSL/ModalResponse``
- ``DiscordCommandDSL/UpdateMessageResponse``

### Message Builder

- ``DiscordCommandDSL/Components``
- ``DiscordCommandDSL/Embed``
- ``DiscordCommandDSL/MessageBody``
- ``DiscordCommandDSL/MessageBuilder``
- ``DiscordCommandDSL/MessageBuilderValue``
- ``DiscordCommandDSL/Text``

### Modal Values

- ``DiscordCommandDSL/AnyModalField``
- ``DiscordCommandDSL/ModalDecodedValues``
- ``DiscordCommandDSL/ModalField``
- ``DiscordCommandDSL/ModalInput``
- ``DiscordCommandDSL/ModalSchema``
- ``DiscordCommandDSL/ModalSelections``
- ``DiscordCommandDSL/ModalValue``
- ``DiscordCommandDSL/ModalValues``

### Slash Command Families

- ``DiscordCommandDSL/SlashCommandBranch``
- ``DiscordCommandDSL/SlashCommandTree``
- ``DiscordCommandDSL/SlashSubcommand``
- ``DiscordCommandDSL/SlashSubcommandGroup``

<!-- Generated by Tools/ci/curate_docc.py; API descriptions live in declaration comments. -->
