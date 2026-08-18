//
//  CompressaoZlib.swift
//  BeagleCore
//
//  Comprime o corpo de requisições grandes para o formato que servidores HTTP
//  entendem — e a armadilha que isto existe para contornar foi MEDIDA, não lida.
//
//  `NSData.compressed(using: .zlib)` da Apple, apesar do nome, NÃO produz um fluxo
//  zlib: produz **deflate cru** (RFC 1951). Verificado no Mac em 12-ago-2026 — os
//  primeiros bytes saem `ed ca`, não `78 xx`, e não há cabeçalho.
//
//  Mandar isso com `Content-Encoding: deflate` faz o servidor responder 400 com
//  "incorrect header check" — também verificado, contra o mesmo express que o
//  serviço de fisiologia usa. O conserto é envelopar: 2 bytes de cabeçalho zlib na
//  frente, Adler-32 do ORIGINAL atrás. Com isso o Node inflou e devolveu byte a
//  byte o mesmo conteúdo.
//
//  POR QUE VALE: no ingest de fisiologia, um lote de 5.000 amostras são 864 KB de
//  JSON — 172,8 bytes por linha. Comprimido cai para ~36 B/linha, 4,8x menos. Para
//  a fila do relógio, que pode ter milhões de amostras, isso é 173 MB → 36 MB.
//
//  E por que NÃO fomos de Apache Arrow: Arrow chegaria a 23 B/linha (7,5x), mas o
//  ganho real que sobra é de CPU, e a CPU não é o gargalo — `JSON.parse` de um lote
//  custa 2,9 ms no servidor, ou 0,6 s para um milhão de amostras inteiro. Não se
//  troca a pilha de serialização de um app clínico para economizar 0,6 segundo.
//

import Foundation

public enum CompressaoZlib {

    /// Abaixo disto o cabeçalho e o custo de CPU não se pagam.
    public static let limiarBytes = 4096

    /// Envelopa em formato zlib (RFC 1950) o que a Apple devolve como deflate cru.
    /// Devolve `nil` quando não vale a pena ou quando a compressão falha — e nesse
    /// caso o chamador manda o original. Comprimir NUNCA pode derrubar um envio:
    /// esta fila carrega dados de saúde que já estão atrasados.
    public static func comprimir(_ dados: Data) -> Data? {
        guard dados.count >= limiarBytes else { return nil }
        guard let cru = try? (dados as NSData).compressed(using: .zlib) as Data else { return nil }

        // Só vale se realmente encolheu — texto já comprimido pode crescer.
        guard cru.count + 6 < dados.count else { return nil }

        var envelope = Data(capacity: cru.count + 6)
        envelope.append(contentsOf: [0x78, 0x9C])   // CM=deflate, janela 32K, sem dicionário
        envelope.append(cru)
        var soma = adler32(dados).bigEndian          // Adler-32 é sobre o ORIGINAL
        withUnsafeBytes(of: &soma) { envelope.append(contentsOf: $0) }
        return envelope
    }

    /// Adler-32 (RFC 1950 §9). Duas somas rolantes módulo 65521.
    static func adler32(_ dados: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        // Fatiado para que o módulo não precise correr a cada byte.
        dados.withUnsafeBytes { bruto in
            var i = 0
            let n = bruto.count
            while i < n {
                let ate = min(i + 5552, n)   // 5552 = maior bloco sem estourar UInt32
                while i < ate {
                    a &+= UInt32(bruto[i])
                    b &+= a
                    i += 1
                }
                a %= 65521
                b %= 65521
            }
        }
        return (b << 16) | a
    }
}
