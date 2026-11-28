//
//  ScienceAndWebBridge.swift
//  BeagleCore
//
//  Pesquisa científica primária (PubMed NCBI E-utilities com abstracts estruturados,
//  DOI/Crossref, EuropePMC, arXiv) + leitor universal de links/páginas/PDFs online
//  + busca web ao vivo (OpenAI web_search_preview + DuckDuckGo fallback).
//

import Foundation

// MARK: - Main Bridge Actor

public actor ScienceAndWebBridge {
    public static let shared = ScienceAndWebBridge()

    public nonisolated static let toolNames: Set<String> = [
        "beagle_search_pubmed",
        "beagle_lookup_scientific_work",
        "beagle_read_url",
        "beagle_web_search"
    ]

    public nonisolated static func isScienceOrWebTool(_ name: String) -> Bool {
        toolNames.contains(name)
    }

    internal let session: URLSession
    internal let allowOpenAIHostedSearch: Bool

    public init(session: URLSession? = nil, allowOpenAIHostedSearch: Bool = true) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 16
            config.timeoutIntervalForResource = 32
            config.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) BeagleCockpit/1.0",
                "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7"
            ]
            self.session = URLSession(configuration: config)
        }
        self.allowOpenAIHostedSearch = allowOpenAIHostedSearch
    }

    // MARK: - OpenAI / Anthropic Tool Schemas

    public nonisolated static func openAIToolDefinitions() -> [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": "beagle_search_pubmed",
                    "description": "Busca artigos científicos biomédicos reais diretamente no PubMed (NCBI E-utilities), retornando PMID, DOI, autores, periódico, ano, tipo de estudo (RCT, meta-análise, revisão) e o ABSTRACT completo.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Consulta científica em inglês para o PubMed (suporta MeSH, autores, operadores AND/OR, ex: 'ketamine treatment resistant depression randomized trial')."
                            ],
                            "max_results": [
                                "type": "integer",
                                "description": "Número de artigos com abstract completo (1 a 8, padrão 5)."
                            ],
                            "sort": [
                                "type": "string",
                                "enum": ["relevance", "pub_date"],
                                "description": "Ordenação: 'relevance' (relevância) ou 'pub_date' (mais recentes primeiro)."
                            ],
                            "min_year": [
                                "type": "integer",
                                "description": "Ano mínimo opcional de publicação (ex: 2023)."
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_lookup_scientific_work",
                    "description": "Resolve um DOI (ex: '10.1056/NEJMoa...'), PMID, identificador arXiv (ex: '2405.12345') ou busca artigos/preprints no Crossref, EuropePMC e arXiv com metadados completos, citações e abstract.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "identifier_or_query": [
                                "type": "string",
                                "description": "DOI ('10.xxxx/...'), PMID ('38412345'), arXiv ID ('2405.12345') ou termos de busca científica."
                            ],
                            "source": [
                                "type": "string",
                                "enum": ["auto", "doi", "arxiv", "europepmc"],
                                "description": "Fonte preferencial ('auto' detecta DOI/PMID/arXiv automaticamente)."
                            ]
                        ],
                        "required": ["identifier_or_query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_read_url",
                    "description": "Acessa e extrai o texto limpo de qualquer URL (página web, artigo científico, link do PubMed/DOI/arXiv ou PDF online) diretamente no dispositivo.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "url": [
                                "type": "string",
                                "description": "URL completa http:// ou https:// para ler."
                            ]
                        ],
                        "required": ["url"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_web_search",
                    "description": "Executa busca na web ao vivo para diretrizes recentes, notícias, documentação técnica, fatos atuais ou páginas públicas com URLs reais para citação.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Consulta de busca na web."
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Unified Dispatcher

    public func execute(name: String, args: [String: Any]) async -> String {
        switch name {
        case "beagle_search_pubmed":
            let query = (args["query"] as? String) ?? ""
            let maxResults = Self.intArg(args["max_results"]) ?? 5
            let sort = (args["sort"] as? String) ?? "relevance"
            let minYear = Self.intArg(args["min_year"])
            return await searchPubMed(query: query, maxResults: maxResults, sort: sort, minYear: minYear)

        case "beagle_lookup_scientific_work":
            let q = (args["identifier_or_query"] as? String) ?? (args["query"] as? String) ?? (args["doi"] as? String) ?? ""
            let src = (args["source"] as? String) ?? "auto"
            return await lookupScientificWork(identifierOrQuery: q, source: src)

        case "beagle_read_url":
            let rawURL = (args["url"] as? String) ?? ""
            return await readURLString(rawURL)

        case "beagle_web_search":
            let query = (args["query"] as? String) ?? ""
            return await webSearch(query: query)

        default:
            return "Ferramenta científica/web desconhecida: \(name)"
        }
    }

    private nonisolated static func intArg(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
