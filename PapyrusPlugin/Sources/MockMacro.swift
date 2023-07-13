import SwiftSyntax
import SwiftSyntaxMacros

public struct MockMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in _: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        handleError {
            guard let type = declaration.as(ProtocolDeclSyntax.self) else {
                throw PapyrusPluginError("@Mock can only be applied to protocols.")
            }

            let name = node.firstArgument ?? "\(type.typeName)Mock"
            return try type.createMock(named: name)
        }
    }
}

extension ProtocolDeclSyntax {
    fileprivate func createMock(named mockName: String) throws -> String {
        try """
        \(access)final class \(mockName): \(typeName) {
            private let notMockedError: Error
            private var mocks: [String: Any]

            \(access)init(notMockedError: Error = PapyrusError("Not mocked")) {
                self.notMockedError = notMockedError
                mocks = [:]
            }

        \(generateMockFunctions())
        }
        """
    }

    private func generateMockFunctions() throws -> String {
        try functions
            .flatMap { try [$0.mockImplementation(), $0.mockerFunction] }
            .map { access + $0 }
            .joined(separator: "\n\n")
    }
}

private extension FunctionDeclSyntax {
    func mockImplementation() throws -> String {
        try validateSignature()

        let notFoundExpression: String
        switch style {
        case .concurrency:
            notFoundExpression = "throw notMockedError"
        case .completionHandler:
            guard let callbackName else {
                throw PapyrusPluginError("Missing @escaping completion handler as final function argument.")
            }

            let unimplementedError = returnResponseOnly ? ".error(notMockedError)" : ".failure(notMockedError)"
            notFoundExpression = """
            \(callbackName)(\(unimplementedError))
            return
            """
        }

        let mockerArguments = parameters.map(\.variableName).joined(separator: ", ")
        let matchExpression: String =
            switch style
        {
        case .concurrency:
            "return try await mocker(\(mockerArguments))"
        case .completionHandler:
            "mocker(\(mockerArguments))"
        }

        return """
        func \(functionName)\(signature) {
            guard let mocker = mocks["\(functionName)"] as? \(mockClosureType) else {
                \(notFoundExpression)
            }

            \(matchExpression)
        }
        """
    }

    var mockerFunction: String {
        """
        func mock\(functionName.capitalizeFirst)(result: @escaping \(mockClosureType)) {
            mocks["\(functionName)"] = result
        }
        """
    }

    private var mockClosureType: String {
        let parameterTypes = parameters.map(\.typeString).joined(separator: ", ")
        let effects = effects.isEmpty ? "" : " \(effects.joined(separator: " "))"
        let returnType = signature.output?.returnType.trimmedDescription ?? "Void"
        return "(\(parameterTypes))\(effects) -> \(returnType)"
    }
}

private extension FunctionParameterSyntax {
    var typeString: String {
        trimmed.type.description
    }
}

private extension String {
    var capitalizeFirst: String {
        prefix(1).capitalized + dropFirst()
    }
}
