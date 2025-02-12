//
//  Interaction+Response.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/10/25.
//

extension Interaction {
    public struct Response: DiscordModel {
        public let type: CallbackType
        public let data: CallbackData?
    }
}

extension Interaction.Response {
    enum CodingKeys: String, CodingKey {
        case type
        case data
    }
    
    public init(from decoder: any Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.type = try container.decode(CallbackType.self, forKey: .type)

         if let message = try? container.decode(CallbackData.Messages.self, forKey: .data) {
             self.data = .message(message)
         } else if let autocomplete = try? container.decode(CallbackData.Autocomplete.self, forKey: .data) {
             self.data = .autocomplete(autocomplete)
         } else if let modal = try? container.decode(CallbackData.Modal.self, forKey: .data) {
             self.data = .modal(modal)
         } else {
             self.data = nil
         }
     }
     
     public func encode(to encoder: any Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encode(type, forKey: .type)
         
         if let data = data {
             switch data {
             case .message(let message):
                 try container.encode(message, forKey: .data)
             case .autocomplete(let autocomplete):
                 try container.encode(autocomplete, forKey: .data)
             case .modal(let modal):
                 try container.encode(modal, forKey: .data)
             }
         }
     }
}
