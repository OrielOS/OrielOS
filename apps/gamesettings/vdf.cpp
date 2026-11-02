// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "vdf.h"

namespace OrielOSGames {

namespace {

struct Token
{
    enum Kind : quint8 { String, Open, Close, End } kind = End;
    QString text;
};

class Lexer
{
public:
    explicit Lexer(const QString &text)
        : m_text(text)
    {
    }

    Token next()
    {
        skipSpaceAndComments();
        if (m_pos >= m_text.size()) {
            return { };
        }
        const QChar c = m_text.at(m_pos);
        if (c == QLatin1Char('{')) {
            ++m_pos;
            return { Token::Open, { } };
        }
        if (c == QLatin1Char('}')) {
            ++m_pos;
            return { Token::Close, { } };
        }
        if (c == QLatin1Char('"')) {
            return quoted();
        }
        QString word;
        while (m_pos < m_text.size()) {
            const QChar w = m_text.at(m_pos);
            if (w.isSpace() || w == QLatin1Char('{') || w == QLatin1Char('}') || w == QLatin1Char('"')) {
                break;
            }
            word.append(w);
            ++m_pos;
        }
        return { Token::String, word };
    }

    bool failed() const { return m_failed; }

private:
    void skipSpaceAndComments()
    {
        while (m_pos < m_text.size()) {
            if (m_text.at(m_pos).isSpace()) {
                ++m_pos;
            } else if (m_text.mid(m_pos, 2) == QLatin1String("//")) {
                while (m_pos < m_text.size() && m_text.at(m_pos) != QLatin1Char('\n')) {
                    ++m_pos;
                }
            } else {
                break;
            }
        }
    }

    Token quoted()
    {
        ++m_pos;
        QString out;
        while (m_pos < m_text.size()) {
            const QChar c = m_text.at(m_pos++);
            if (c == QLatin1Char('"')) {
                return { Token::String, out };
            }
            if (c == QLatin1Char('\\') && m_pos < m_text.size()) {
                const QChar e = m_text.at(m_pos++);
                if (e == QLatin1Char('n')) {
                    out.append(QLatin1Char('\n'));
                } else if (e == QLatin1Char('t')) {
                    out.append(QLatin1Char('\t'));
                } else {
                    out.append(e);
                }
                continue;
            }
            out.append(c);
        }
        m_failed = true;
        return { };
    }

    const QString &m_text;
    qsizetype m_pos = 0;
    bool m_failed = false;
};

bool isCondition(const QString &text)
{
    return text.startsWith(QLatin1Char('[')) && text.endsWith(QLatin1Char(']'));
}

// Reads entries until a closing brace (inside a block) or the end (at the top).
bool parseEntries(Lexer &lexer, QList<VdfNode> &out, bool inside)
{
    while (true) {
        Token key = lexer.next();
        if (lexer.failed()) {
            return false;
        }
        if (key.kind == Token::End) {
            return !inside;
        }
        if (key.kind == Token::Close) {
            return inside;
        }
        if (key.kind != Token::String) {
            return false;
        }
        Token value = lexer.next();
        if (value.kind == Token::String && isCondition(value.text)) {
            value = lexer.next();
        }
        VdfNode node;
        node.key = key.text;
        if (value.kind == Token::Open) {
            node.block = true;
            if (!parseEntries(lexer, node.children, true)) {
                return false;
            }
        } else if (value.kind == Token::String) {
            node.value = value.text;
        } else {
            return false;
        }
        out.append(node);
    }
}

QString escape(const QString &text)
{
    QString out = text;
    out.replace(QLatin1Char('\\'), QLatin1String("\\\\"));
    out.replace(QLatin1Char('"'), QLatin1String("\\\""));
    return out;
}

void writeEntries(const QList<VdfNode> &entries, int depth, QString &out)
{
    const QString indent(depth, QLatin1Char('\t'));
    for (const VdfNode &node : entries) {
        if (node.block) {
            out += indent + QLatin1Char('"') + escape(node.key) + QLatin1String("\"\n");
            out += indent + QLatin1String("{\n");
            writeEntries(node.children, depth + 1, out);
            out += indent + QLatin1String("}\n");
        } else {
            out += indent + QLatin1Char('"') + escape(node.key) + QLatin1String("\"\t\t\"") + escape(node.value) + QLatin1String("\"\n");
        }
    }
}

} // namespace

VdfNode *VdfNode::child(const QString &name)
{
    for (VdfNode &node : children) {
        if (node.key.compare(name, Qt::CaseInsensitive) == 0) {
            return &node;
        }
    }
    return nullptr;
}

const VdfNode *VdfNode::child(const QString &name) const
{
    for (const VdfNode &node : children) {
        if (node.key.compare(name, Qt::CaseInsensitive) == 0) {
            return &node;
        }
    }
    return nullptr;
}

const VdfNode *VdfNode::find(const QStringList &path) const
{
    const VdfNode *node = this;
    for (const QString &name : path) {
        node = node->child(name);
        if (!node) {
            return nullptr;
        }
    }
    return node;
}

VdfNode &VdfNode::ensure(const QStringList &path)
{
    VdfNode *node = this;
    for (const QString &name : path) {
        VdfNode *next = node->child(name);
        if (!next) {
            node->children.append(VdfNode { name, { }, { }, true });
            next = &node->children.last();
        }
        next->block = true;
        node = next;
    }
    return *node;
}

QString VdfNode::valueOf(const QString &name) const
{
    const VdfNode *node = child(name);
    return node && !node->block ? node->value : QString();
}

void VdfNode::set(const QString &name, const QString &value)
{
    if (VdfNode *node = child(name)) {
        node->block = false;
        node->children.clear();
        node->value = value;
        return;
    }
    children.append(VdfNode { name, value, { }, false });
}

bool VdfNode::remove(const QString &name)
{
    return children.removeIf([&name](const VdfNode &node) { return node.key.compare(name, Qt::CaseInsensitive) == 0; }) > 0;
}

std::optional<VdfNode> parseVdf(const QString &text)
{
    Lexer lexer(text);
    VdfNode root;
    root.block = true;
    if (!parseEntries(lexer, root.children, false)) {
        return std::nullopt;
    }
    return root;
}

QString writeVdf(const VdfNode &root)
{
    QString out;
    writeEntries(root.children, 0, out);
    return out;
}

} // namespace OrielOSGames
