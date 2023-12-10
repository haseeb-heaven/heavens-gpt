import SwiftUI
import Combine

struct ServerResponse: Codable {
    var choices: [Choice]
}

struct Choice: Codable {
    var message: Content
}

struct Content: Codable {
    var role: String
    var content: String
}

struct ChatRequest: Codable {
    var messages: [Message]
    var model: String
    var temperature: Double
    var maxTokens: Int
    var stream: Bool

    enum CodingKeys: String, CodingKey {
        case messages, model, temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

struct Message: Codable {
    var role: String
    var content: String
}

class ChatViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var messages: [Content] = []
    @Published var errorMessage: String? = nil

    func getChatCompletion(textInput:String){
        
        let messages: [Message] = [
            Message(role: "system", content: "You are a senior software developer called HeavenHM, experienced in multiple programming languages and software architectures. You provide detailed, clear, and efficient solutions."),
            Message(role: "user", content: textInput)
        ]

        let chatRequest = ChatRequest(
            messages: messages,
            model: "gpt-3.5-turbo",
            temperature: 0.1,
            maxTokens: 2048,
            stream: false
        )
        
        guard let url = URL(string: "https://heaven-gpt.haseebmir.repl.co/chat/completions") else {
            errorMessage = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try? JSONEncoder().encode(chatRequest)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error making request: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }

                do {
                    let serverResponse = try JSONDecoder().decode(ServerResponse.self, from: data)
                    self?.messages.append(contentsOf: serverResponse.choices.map(\.message))
                } catch {
                    self?.errorMessage = "Error decoding JSON: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack {
            if let errorMessage = viewModel.errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages, id: \.content) { message in
                        Text("\(message.role): \(message.content)")
                    }
                }
                .padding()
            }

            HStack {
                TextField("Enter Prompt", text: $viewModel.prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Send") {
                    let textInput = viewModel.prompt.description
                    viewModel.getChatCompletion(textInput: textInput)
                    viewModel.prompt = ""
                }
            }.padding()
        }
        .frame(width: 600, height: 400)
    }
}
