module matn.editor.braces;

import std.algorithm : min, max;
import matn.ui.grid.cell : Color, CellStyle, CellAttr;
import matn.extension.base;

/// Bracket match location
struct BracketMatch
{
    bool found = false;
    int openRow;
    int openCol;
    int closeRow;
    int closeCol;
}

/**
 * Rainbow Brackets Engine:
 * Analyzes nested code blocks and maps each nesting depth
 * to a distinct color from the rainbow palette.
 */
class ColorBracesExtension : Extension
{
    // 5-color rainbow palette for dark themes (soft pastels)
    private static immutable Color[5] s_rainbowColorsDark = [
        Color(226, 183, 20, 255),  // Gold
        Color(218, 112, 214, 255), // Orchid
        Color(87, 199, 231, 255),  // Sky Blue
        Color(255, 140, 105, 255), // Coral
        Color(152, 195, 121, 255)  // Green
    ];

    // 5-color rainbow palette for light themes (deep, dark saturated tones)
    private static immutable Color[5] s_rainbowColorsLight = [
        Color(170, 115, 0, 255),   // Deep Dark Gold / Amber
        Color(135, 35, 150, 255),  // Deep Violet / Purple
        Color(10, 100, 180, 255),  // Deep Blue
        Color(175, 45, 25, 255),   // Deep Crimson / Rust
        Color(20, 120, 45, 255)    // Deep Forest Green
    ];

    private static immutable Color s_matchBgColorDark = Color(70, 90, 140, 255);
    private static immutable Color s_matchBgColorLight = Color(195, 220, 255, 255);

    // Document-wide bracket colors: row -> (col -> Color)
    private Color[int][size_t] _bracketColors;

    const(Color)[] rainbowColors(bool isLight = false) const pure nothrow
    {
        return isLight ? s_rainbowColorsLight[] : s_rainbowColorsDark[];
    }

    Color matchBgColor(bool isLight = false) const pure nothrow
    {
        return isLight ? s_matchBgColorLight : s_matchBgColorDark;
    }

    Color colorForDepth(int depth, bool isLight = false) const pure nothrow
    {
        auto palette = isLight ? s_rainbowColorsLight[] : s_rainbowColorsDark[];
        return palette[depth % palette.length];
    }

    void invalidateCache()
    {
        _bracketColors.clear();
    }

    this()
    {
        super(ExtensionManifest(
            "matn.braces",
            "Color Braces (Rainbow Brackets)",
            "1.2.0",
            "Matn Core",
            "Rainbow nested bracket coloring for (), [], {} and matching bracket pair highlight",
            true
        ));
        this._enabled = true;
    }

    override protected void onActivate()
    {
        if (_context)
        {
            _context.registerSetting("EDITOR", "Color Braces", "Rainbow brackets and matching pair highlight", {
                _enabled = !_enabled;
            });
        }
    }

    /**
     * Fast bracket predicates.
     * Matches standard ASCII bracket pairs: (), [], {}.
     */
    static bool isBracket(dchar c) pure nothrow @safe
    {
        // Check for round, square, or curly brackets
        return c == '(' || c == ')' ||
               c == '[' || c == ']' ||
               c == '{' || c == '}';
    }

    static bool isOpenBracket(dchar c) pure nothrow @safe
    {
        return c == '(' || c == '[' || c == '{';
    }

    static bool isCloseBracket(dchar c) pure nothrow @safe
    {
        return c == ')' || c == ']' || c == '}';
    }

    static dchar getMatchingBracket(dchar c) pure nothrow @safe
    {
        switch (c)
        {
        case '(': return ')';
        case ')': return '(';
        case '[': return ']';
        case ']': return '[';
        case '{': return '}';
        case '}': return '{';
        default: return c;
        }
    }

    static Color colorForDepth(int depth, bool isLight = false) pure nothrow
    {
        auto palette = isLight ? s_rainbowColorsLight[] : s_rainbowColorsDark[];
        return palette[depth % palette.length];
    }

    /// Scans buffer lines and identifies bracket characters
    /// ignoring string literals and comments
    void analyzeBuffer(const(dchar[][]) lines, bool isLight = false)
    {
        _bracketColors.clear();
        if (!_enabled || lines.length == 0) return;

        enum State
        {
            code,
            lineComment,
            blockComment,
            dquote,
            squote,
            backtick
        }

        State state = State.code;
        bool inEscape = false;
        dchar prev = 0;
        int depth = 0;

        foreach (r, ref line; lines)
        {
            // Line comments and single-quote char literals do not cross line boundaries
            if (state == State.lineComment || state == State.squote)
            {
                state = State.code;
                inEscape = false;
            }

            foreach (cIdx, c; line)
            {
                final switch (state)
                {
                case State.code:
                    if (prev == '/' && c == '/')
                    {
                        state = State.lineComment;
                    }
                    else if (prev == '/' && c == '*')
                    {
                        state = State.blockComment;
                    }
                    else if (c == '#')
                    {
                        state = State.lineComment;
                    }
                    else if (c == '"')
                    {
                        state = State.dquote;
                        inEscape = false;
                    }
                    else if (c == '\'')
                    {
                        state = State.squote;
                        inEscape = false;
                    }
                    else if (c == '`')
                    {
                        state = State.backtick;
                    }
                    else if (isOpenBracket(c))
                    {
                        _bracketColors[r][cast(int) cIdx] = colorForDepth(depth, isLight);
                        depth++;
                    }
                    else if (isCloseBracket(c))
                    {
                        if (depth > 0)
                            depth--;
                        _bracketColors[r][cast(int) cIdx] = colorForDepth(depth, isLight);
                    }
                    break;
                case State.lineComment:
                    break;
                case State.blockComment:
                    if (prev == '*' && c == '/')
                        state = State.code;
                    break;
                case State.dquote:
                    if (inEscape)
                        inEscape = false;
                    else if (c == '\\')
                        inEscape = true;
                    else if (c == '"')
                        state = State.code;
                    break;
                case State.squote:
                    if (inEscape)
                        inEscape = false;
                    else if (c == '\\')
                        inEscape = true;
                    else if (c == '\'')
                        state = State.code;
                    break;
                case State.backtick:
                    if (c == '`')
                        state = State.code;
                    break;
                }
                prev = c;
            }
            prev = '\n';
            inEscape = false;
        }
    }

    /// Color brackets in a line with rainbow colors based on buffer-wide nesting depth
    void applyRainbow(size_t row, const(dchar)[] line, ref Color[] outFg)
    {
        if (!_enabled || line.length == 0) return;
        if (outFg.length < line.length)
            outFg.length = line.length;

        if (auto pRow = row in _bracketColors)
        {
            foreach (col, color; *pRow)
            {
                if (col < outFg.length)
                    outFg[col] = color;
            }
        }
    }

    /// Check whether a bracket at the given position is part of valid code syntax (not in strings/comments)
    bool isValidBracket(int r, int c) const
    {
        if (auto pRow = r in _bracketColors)
            return (c in *pRow) !is null;
        return false;
    }

    /// Find matching bracket pair for cursor position in buffer lines
    BracketMatch findMatchingBracket(const(dchar[][]) lines, int curRow, int curCol)
    {
        BracketMatch res;
        if (!_enabled || lines.length == 0 || curRow < 0 || curRow >= lines.length)
            return res;

        if (_bracketColors.length == 0)
            analyzeBuffer(lines);

        auto curLine = lines[curRow];
        int targetCol = -1;
        dchar targetChar = ' ';

        // Check if cursor is on a bracket, or right after a bracket
        if (curCol < curLine.length && isBracket(curLine[curCol]) && isValidBracket(curRow, curCol))
        {
            targetCol = curCol;
            targetChar = curLine[curCol];
        }
        else if (curCol > 0 && curCol - 1 < curLine.length && isBracket(curLine[curCol - 1]) && isValidBracket(curRow, curCol - 1))
        {
            targetCol = curCol - 1;
            targetChar = curLine[curCol - 1];
        }

        if (targetCol == -1)
            return res;

        dchar matchChar = getMatchingBracket(targetChar);

        if (isOpenBracket(targetChar))
        {
            // Search forward for closing bracket
            int depth = 1;
            int r = curRow;
            int c = targetCol + 1;

            while (r < lines.length)
            {
                auto line = lines[r];
                while (c < line.length)
                {
                    if (line[c] == targetChar && isValidBracket(r, c))
                        depth++;
                    else if (line[c] == matchChar && isValidBracket(r, c))
                    {
                        depth--;
                        if (depth == 0)
                        {
                            res.found = true;
                            res.openRow = curRow;
                            res.openCol = targetCol;
                            res.closeRow = r;
                            res.closeCol = c;
                            return res;
                        }
                    }
                    c++;
                }
                r++;
                c = 0;
            }
        }
        else
        {
            // Search backward for opening bracket
            int depth = 1;
            int r = curRow;
            int c = targetCol - 1;
            if (c < 0)
            {
                r--;
                c = (r >= 0) ? cast(int) lines[r].length - 1 : -1;
            }

            while (r >= 0)
            {
                auto line = lines[r];
                while (c >= 0)
                {
                    if (line[c] == targetChar && isValidBracket(r, c))
                    {
                        depth++;
                    }
                    else if (line[c] == matchChar && isValidBracket(r, c))
                    {
                        depth--;
                        if (depth == 0)
                        {
                            res.found = true;
                            res.openRow = r;
                            res.openCol = c;
                            res.closeRow = curRow;
                            res.closeCol = targetCol;
                            return res;
                        }
                    }
                    c--;
                }
                r--;
                c = (r >= 0) ? cast(int) lines[r].length - 1 : -1;
            }
        }

        return res;
    }

    /// Background color override for matching bracket cells
    Color matchBgColor() const { return s_matchBgColorDark; }

    /**
     * Determines whether matching bracket highlight is active for a position.
     * Used by editor rendering pass to shade character cells.
     */
    bool isBracketMatchPosition(int row, int col, BracketMatch m) const pure nothrow @safe
    {
        return m.found && ((row == m.openRow && col == m.openCol) || (row == m.closeRow && col == m.closeCol));
    }
}

unittest
{
    auto ext = new ColorBracesExtension();

    // 1. Basic matching
    dchar[][] code = [
        "void test() {"d.dup,
        "    int[3] arr = [1, 2, 3];"d.dup,
        "    if (arr[0] == 1) {"d.dup,
        "        return;"d.dup,
        "    }"d.dup,
        "}"d.dup
    ];
    ext.analyzeBuffer(code);

    auto m = ext.findMatchingBracket(code, 0, 12); // '{'
    assert(m.found);
    assert(m.openRow == 0 && m.openCol == 12);
    assert(m.closeRow == 5 && m.closeCol == 0);

    // 2. Character literals and escaped quotes
    dchar[][] charCode = [
        "void test() {"d.dup,
        "    char a = '\'';"d.dup,
        "    char b = '\\\\';"d.dup,
        "    auto brace = h.indexOf('{');"d.dup,
        "    if (true) {"d.dup,
        "        int x = 1;"d.dup,
        "    }"d.dup,
        "}"d.dup
    ];
    ext.analyzeBuffer(charCode);

    // '{' in indexOf('{') (column 28) should not be recognized as an open bracket
    auto mChar = ext.findMatchingBracket(charCode, 3, 28);
    assert(!mChar.found, "'{' in char literal must not match");

    // '{' on line 0 should match line 7 '}'
    auto mOuter = ext.findMatchingBracket(charCode, 0, 12);
    assert(mOuter.found);
    assert(mOuter.closeRow == 7 && mOuter.closeCol == 0);

    // '{' on line 4 should match line 6 '}'
    auto mInner = ext.findMatchingBracket(charCode, 4, 14);
    assert(mInner.found);
    assert(mInner.closeRow == 6 && mInner.closeCol == 4);
}
