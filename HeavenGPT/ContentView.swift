import SwiftUI
import Combine
import AppKit
import Highlightr

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

struct MessageSegment: Hashable {
    let id = UUID()
    let text: String
    let isCode: Bool
}


// MARK: - ChatViewModel
class ChatViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    
    private var logger: Logger?

    init() {
        setupLogger()
    }
    
    private func setupLogger() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("heaven-gpt-logs.txt")
        logger = Logger(fileURL: fileURL)
    }
    
    func log(_ message: String) {
        logger?.log(message)
    }

    func getChatCompletion(textInput: String) {
        
        // Adding guard statements to check for empty input
        guard !textInput.isEmpty else {
            errorMessage = "Message is empty"
            log("Message is empty")
            return
        }

        log("Getting chat completion for message: \(textInput)")

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
        log("Chat request: \(chatRequest)")

        let baseUrl = "https://heaven-gpt.haseebmir.repl.co" // The Heaven-GPT API is hosted on Repl.it
        guard let url = URL(string: baseUrl.appending("/chat/completions")) else {
            errorMessage = "Invalid URL"
            log("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        log("Request headers: \(request.allHTTPHeaderFields ?? [:])")

        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
            log("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "")")
        } catch {
            errorMessage = "Error encoding JSON: \(error.localizedDescription)"
            log("Error encoding JSON: \(error.localizedDescription)")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Error making request: \(error.localizedDescription)"
                    self?.log("Error making request: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    self?.errorMessage = "No data received"
                    self?.log("No data received")
                    return
                }

                do {
                    guard let response = response as? HTTPURLResponse else {
                        self?.errorMessage = "Invalid response"
                        self?.log("Invalid response")
                        return
                    }

                    guard response.statusCode == 200 else {
                        self?.errorMessage = "Invalid response code: \(response.statusCode)"
                        self?.log("Invalid response code: \(response.statusCode)")
                        return
                    }

                    let serverResponse = try JSONDecoder().decode(ServerResponse.self, from: data)
                    let newMessages = serverResponse.choices.map { ChatMessage(role: $0.message.role, content: $0.message.content) }
                    self?.messages.append(contentsOf: newMessages)
                } catch {
                    self?.errorMessage = "Error decoding JSON: \(error.localizedDescription)"
                    self?.log("Error decoding JSON: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    func sendMessage() {
        
        // Adding guard statements to check for empty input
        guard !prompt.isEmpty else {
            errorMessage = "Message is empty"
            log("Message is empty")
            return
        }
        log("Sending message: \(prompt)")

        let newMessage = ChatMessage(role: "User", content: prompt)
        messages.append(newMessage)
        log("Message added: \(newMessage.content)")
        getChatCompletion(textInput: prompt)
        prompt = ""
    }

    func saveMessageToFile(_ message: ChatMessage, filename: String = "data.txt") {
        log("Saving message to file: \(message.content)")
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        log("File URL: \(fileURL)")
        do {
            try message.content.write(to: fileURL, atomically: true, encoding: .utf8)
            log("Saved to file: \(fileURL)")
            // open file in text editor.
            NSWorkspace.shared.open(fileURL)
            
        } catch {
            showAlertMessage(message: "Error saving to file: \(error.localizedDescription)", title: "Error")
            log("Error saving to file: \(error.localizedDescription)")
        }
    }
    
    func deleteMessage(_ message: ChatMessage) {
        log("Deleting message: \(message.content)")
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
            log("Message deleted: \(message.content)")
        }
    }
    
    func showAlertMessage(message: String,title: String = "OK"){
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: title)
        alert.accessoryView = NSHostingView(rootView: ErrorView(errorMessage: errorMessage))
        alert.runModal()
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
    @ObservedObject var viewModel: ChatViewModel
    var deleteMessage: (ChatMessage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { message in
                    ChatMessageView(message: message,
                        deleteAction: {
                            deleteMessage(message)
                        },
                        copyAction: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(message.content, forType: .string)
                            viewModel.log("Message copied: \(message.content)")
                        },
                        saveAction: {
                            viewModel.saveMessageToFile(message)
                            viewModel.log("Message saved to file: \(message.content)")
                        })
                }
            }
        }
    }
}


struct SyntaxHighlightingView: NSViewRepresentable {
    var code: String
    var language: String

    func makeNSView(context: Context) -> NSView {
        let highlightr = Highlightr()!
        highlightr.setTheme(to: "paraiso-dark")

        // Use Highlightr to highlight the code
        let highlightedAttributedString = highlightr.highlight(code, as: language) ?? NSAttributedString(string: code)

        let textView = NSTextView(frame: .zero, textContainer: NSTextContainer(size: CGSize(width: 500, height: 250)))
        textView.isEditable = false
        textView.backgroundColor = NSColor.clear

        // Set the highlighted code to the NSTextView
        textView.textStorage?.setAttributedString(highlightedAttributedString)
        
        return textView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let textView = nsView as? NSTextView {
            // Update the NSTextView with highlighted text if needed
            let highlightedAttributedString = Highlightr()!.highlight(code, as: language) ?? NSAttributedString(string: code)
            textView.textStorage?.setAttributedString(highlightedAttributedString)
        }
    }
}


struct ChatMessageView: View {
    var message: ChatMessage
    var deleteAction: () -> Void
    var copyAction: () -> Void
    var saveAction: () -> Void
    var viewModel = ChatViewModel()
    var parsedMessage: [MessageSegment] = []

    init(message: ChatMessage, deleteAction: @escaping () -> Void, copyAction: @escaping () -> Void, saveAction: @escaping () -> Void) {
        self.message = message
        self.deleteAction = deleteAction
        self.copyAction = copyAction
        self.saveAction = saveAction
        self.parsedMessage = self.parseMessage(message.content)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(parsedMessage, id: \.id) { segment in
                if segment.isCode {
                    SyntaxHighlightingView(code: segment.text, language: "swift").frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if segment.text.contains("```"){
                        SyntaxHighlightingView(code: segment.text, language: "swift").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    else{
                        Text(segment.text)
                            .foregroundColor(message.role == "User" ? .blue : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        HStack {
            Spacer()
            Button(action: copyAction) {
                Image(systemName: "doc.on.doc")
            }
            Button(action: saveAction) {
                Image(systemName: "square.and.arrow.down")
            }
            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
    }
    
    func parseMessage(_ message: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        let components = message.components(separatedBy: "```")
        viewModel.log("Message components: \(components)")

        var isCode = false
        for component in components {
            if !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if isCode {
                    // Split by new lines and ignore the first line if it's a language specifier.
                    let lines = component.split(separator: "\n", omittingEmptySubsequences: false)
                    let codeWithoutLanguage = lines.dropFirst().joined(separator: "\n")
                    viewModel.log("Code without language: \(codeWithoutLanguage)")
                    segments.append(MessageSegment(text: codeWithoutLanguage, isCode: true))
                } else {
                    segments.append(MessageSegment(text: component, isCode: false))
                }
            }
            isCode.toggle()
        }
        viewModel.log("Parsed message: \(segments)")
        return segments
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
                .frame(minHeight: 100, maxHeight: 100)
                .font(.body)
                .padding()

            Button("Send", action: {
                sendAction()
            })
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    var body: some View {
        VStack {
            
            HStack{
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                
                Text("Heaven GPT")
                    .font(.largeTitle)
                    .padding()
            }
            
            Text("Welcome, how can I help you today?")
                .font(.title)
                .padding()

            ScrollView {
                ForEach(viewModel.messages) { message in
                    ChatMessageView(message: message,
                        deleteAction: {
                            viewModel.deleteMessage(message)
                            viewModel.log("Message deleted: \(message.content)")
                        },
                        copyAction: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(message.content, forType: .string)
                            viewModel.log("Message copied: \(message.content)")
                        },
                        saveAction: {
                            viewModel.saveMessageToFile(message)
                            viewModel.log("Message saved to file: \(message.content)")
                        })
                }
            }.frame(width: 600, height: 300)
                .padding()

            MessageInputView(prompt: $viewModel.prompt, sendAction: {
                viewModel.sendMessage()
                viewModel.log("Message sent: \(viewModel.prompt)")
            })
        }
        .frame(width: 600, height: 400)
        .padding()
    }
}
