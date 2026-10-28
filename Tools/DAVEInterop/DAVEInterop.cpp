// File: Tools/DAVEInterop/DAVEInterop.cpp
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#include <mls/state.h>
#include <iostream>
#include <stdexcept>
#include <string>

using namespace MLS_NAMESPACE;

/// Reads at most one MiB of hexadecimal test input without retaining or printing it.
/// - Returns: Exact decoded bytes, including empty vectors where the protocol permits.
/// - Throws: A fixed category on EOF, excessive length or malformed hexadecimal.
static bytes read_bytes()
{
    std::string line;
    while (true) {
        const auto next = std::cin.get();
        if (next == '\n') break;
        if (next == EOF || line.size() >= 2097152) throw std::runtime_error("input");
        const auto c = static_cast<char>(next);
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) throw std::runtime_error("input");
        line.push_back(c);
    }
    if (line.size() % 2 != 0) throw std::runtime_error("input");
    return from_hex(line);
}

/// Fails one independent validation gate without disclosing input or native error text.
/// - Parameters:
///   - valid: True only when the preceding native check succeeded.
static void require(bool valid)
{
    if (!valid) throw std::runtime_error("validation");
}

/// Exchanges synthetic public packages and candidates through anonymous pipes only.
/// MLS++ independently decodes complete MLSMessage + bare Welcome, verifies signatures,
/// references, initial epoch and signer invariants, joins the Welcome and compares the
/// epoch authenticator. No private key is exported; diagnostics contain fixed stages only.
/// - Returns: Zero only after all checks pass; one after a fixed, sanitized failure stage.
int main()
{
    const char* stage = "native.package";
    try {
        const CipherSuite suite{CipherSuite::ID::P256_AES128GCM_SHA256_P256};
        auto init = HPKEPrivateKey::generate(suite);
        auto leaf = HPKEPrivateKey::generate(suite);
        auto signer = SignaturePrivateKey::generate(suite);
        const auto credential = Credential::basic(bytes{0, 0, 0, 0, 0, 0, 0, 2});
        const auto node = LeafNode{suite, leaf.public_key, signer.public_key, credential,
            Capabilities::create_default(), Lifetime::create_default(), {}, signer};
        const auto package = KeyPackage{suite, init.public_key, node, {}, signer};
        std::cout << to_hex(tls::marshal(MLSMessage(package))) << std::endl;

        stage = "native.initial_context";
        const auto creator = tls::get<MLSMessage>(read_bytes());
        const auto creator_package = var::get<KeyPackage>(creator.message);
        const auto external = tls::get<ExternalSender>(read_bytes());
        const auto proposal = tls::get<MLSMessage>(read_bytes());
        const auto candidate_bytes = read_bytes();
        const auto expected_authenticator = read_bytes();
        require(creator_package.verify());
        ExtensionList extensions;
        extensions.add(ExternalSendersExtension{{external}});
        TreeKEMPublicKey initial_tree(suite);
        initial_tree.add_leaf(creator_package.leaf_node);
        initial_tree.set_hash_all();

        stage = "native.candidate_decode";
        tls::istream stream(candidate_bytes.as_vec());
        MLSMessage message;
        Welcome welcome;
        stream >> message >> welcome;
        require(stream.empty());
        require(bytes(tls::marshal(message)) + bytes(tls::marshal(welcome)) == candidate_bytes);
        require(message.version == ProtocolVersion::mls10 && message.wire_format() == WireFormat::mls_public_message);
        const auto content = var::get<PublicMessage>(message.message).authenticated_content();
        require(content.content.epoch == 0 && content.content.content_type() == ContentType::commit);
        require(content.content.sender.sender_type() == SenderType::member);
        require(var::get<MemberSender>(content.content.sender.sender).sender == LeafIndex(0));
        const auto context = GroupContext{suite, content.content.group_id, 0, initial_tree.root_hash(), {}, extensions};
        require(content.content.group_id == bytes({0, 0, 0, 0, 0, 0, 0, 4}));

        stage = "native.signatures_references";
        require(content.verify(suite, creator_package.leaf_node.signature_key, context));
        const auto proposed = var::get<PublicMessage>(proposal.message).authenticated_content();
        require(proposed.content.epoch == 0 && proposed.content.group_id == context.group_id);
        require(proposed.content.sender.sender_type() == SenderType::external);
        require(proposed.verify(suite, external.signature_key, std::nullopt));
        const auto commit = var::get<Commit>(content.content.content);
        require(commit.proposals.size() == 1);
        require(var::get<ProposalRef>(commit.proposals[0].content) == suite.ref(proposed));
        require(commit.path.has_value());
        const auto path_leaf = commit.path->leaf_node;
        require(path_leaf.credential == creator_package.leaf_node.credential);
        require(path_leaf.signature_key == creator_package.leaf_node.signature_key);
        require(path_leaf.encryption_key != creator_package.leaf_node.encryption_key);
        require(path_leaf.verify(suite, LeafNode::MemberBinding{context.group_id, LeafIndex(0)}));
        require(welcome.cipher_suite.cipher_suite() == suite.cipher_suite());
        require(welcome.secrets.size() == 1 && welcome.secrets[0].new_member == suite.ref(package));

        stage = "native.welcome_join";
        const auto joined = State{init, leaf, signer, package, welcome, std::nullopt, {}};
        require(joined.epoch() == 1 && joined.group_id() == context.group_id);
        require(tls::marshal(joined.extensions()) == tls::marshal(extensions));
        stage = "native.epoch_agreement";
        require(joined.epoch_authenticator() == expected_authenticator);
        std::cout << "accepted" << std::endl;
        return 0;
    } catch (...) {
        std::cout << "rejected:" << stage << std::endl;
        return 1;
    }
}
