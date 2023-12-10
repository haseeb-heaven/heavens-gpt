import SwiftUI
import Combine

// MARK: - ServerResponse, Choice, Content, ChatRequest, Message

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

// MARK: - ChatViewModel

class ChatViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false

    func getChatCompletion(textInput: String) {
        self.isLoading = true
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

        let baseUrl = "https://heaven-gpt.haseebmir.repl.co"
        guard let url = URL(string: baseUrl.appending("/chat/completions")) else {
            errorMessage = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            errorMessage = "Error encoding JSON: \(error.localizedDescription)"
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Error making request: \(error.localizedDescription)"
                    return
                }

                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }

                do {
                    guard let response = response as? HTTPURLResponse else {
                        self?.errorMessage = "Invalid response"
                        return
                    }

                    guard response.statusCode == 200 else {
                        self?.errorMessage = "Invalid response code: \(response.statusCode)"
                        return
                    }

                    let serverResponse = try JSONDecoder().decode(ServerResponse.self, from: data)
                    let newMessages = serverResponse.choices.map { ChatMessage(role: $0.message.role, content: $0.message.content) }
                    self?.messages.append(contentsOf: newMessages)
                } catch {
                    self?.errorMessage = "Error decoding JSON: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    func sendMessage() {
        guard !prompt.isEmpty else {
            errorMessage = "Message is empty"
            return
        }
        let newMessage = ChatMessage(role: "User", content: prompt)
        messages.append(newMessage)
        getChatCompletion(textInput: prompt)
        prompt = ""
    }

    func deleteMessage(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }
    }
}

// MARK: - ChatMessage Model

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: String
    var content: String
}

// MARK: - ErrorView

struct ErrorView: View {
    var errorMessage: String?

    var body: some View {
        if let errorMessage = errorMessage {
            Text("Error: \(errorMessage)")
                .foregroundColor(.red)
        }
    }
}

// MARK: - ChatScrollView
struct ChatScrollView: View {
    @Binding var messages: [ChatMessage]
    var deleteMessage: (ChatMessage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { message in
                    ChatMessageView(message: message) {
                        if let index = messages.firstIndex(where: { $0.id == message.id }) {
                            deleteMessage(messages[index])
                        }
                    }
                }
            }
        }
    }
}


// MARK: - ChatMessageView

struct ChatMessageView: View {
    var message: ChatMessage
    var deleteAction: () -> Void

    var body: some View {
        HStack {
            Text("\(message.role): \(message.content)")
                .foregroundColor(message.role == "User" ? .blue : .green)
            Spacer()
            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
    }
}



// MARK: - MessageInputView

struct MessageInputView: View {
    @Binding var prompt: String
    var sendAction: () -> Void

    var body: some View {
        HStack {
            TextEditor(text: $prompt)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(height: 100)

            Button("Send", action: sendAction)
        }
    }
}

// MARK: - ContentView (for reference)
struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else {
                ErrorView(errorMessage: viewModel.errorMessage)
                ChatScrollView(messages: $viewModel.messages, deleteMessage: viewModel.deleteMessage)
                MessageInputView(prompt: $viewModel.prompt, sendAction: viewModel.sendMessage)
            }
        }
        .frame(width: 600, height: 400)
        .padding()
    }
}

#Preview{
    ContentView()
}
