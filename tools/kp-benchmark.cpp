// Standalone measurement adapter, not the CRengine formatter. See doc/KP_BENCHMARK.md.
#include "../base/thirdparty/kpvcrlib/crengine/crengine/include/lvkplinebreak.h"
#include <hb-ft.h>
#include <cassert>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

struct Metrics {
    int natural = 0, spaces = 0, stretch = 0, shrink = 0;
    bool ragged = false, feasible = false, has_ratio = false;
    double ratio = 0, capacity_ratio = 0;
    int badness = 0;
};

static Metrics measure(const std::vector<KPItem>& items, int start, int end, int width) {
    Metrics m;
    m.ragged = end == static_cast<int>(items.size()) - 1;
    for (int i = start; i < end; ++i) {
        const auto& item = items[i];
        if (item.type == KPItem::PENALTY || (m.ragged && i == end - 1))
            continue;
        m.natural += item.width;
        m.spaces += item.adjustable;
        m.stretch += item.stretch;
        m.shrink += item.shrink;
    }
    int delta = width - m.natural;
    m.has_ratio = !m.ragged || delta < 0;
    m.feasible = delta >= 0 ? m.ragged || delta <= m.stretch : -delta <= m.shrink;
    if (!m.has_ratio)
        return m;
    if (m.spaces)
        m.ratio = static_cast<double>(delta) / m.spaces;
    else if (delta)
        m.ratio = std::copysign(INFINITY, delta);
    int capacity = delta >= 0 ? m.stretch : m.shrink;
    m.capacity_ratio = capacity ? static_cast<double>(delta) / capacity
                               : delta ? std::copysign(INFINITY, delta) : 0;
    double b = 100 * std::pow(std::abs(m.capacity_ratio), 3);
    m.badness = delta < -m.shrink || b >= KP_INFINITY ? KP_INFINITY
               : static_cast<int>(std::floor(b + 0.5));
    return m;
}

static void finish(std::vector<KPItem>& items) {
    items.push_back({KPItem::PENALTY, 0, 0, 0, KP_INFINITY, false, 0, 0, 0});
    items.push_back({KPItem::GLUE, 0, 1000000, 0, 0, false, 0, 0, 0});
    items.push_back({KPItem::PENALTY, 0, 0, 0, -KP_INFINITY, false, 0, 0, 0});
}

static void selfcheck() {
    std::vector<KPItem> items;
    for (int i = 0; i < 3; ++i) {
        if (i) items.push_back({KPItem::GLUE, 3, 1, 1, 0, false, 0, 3, 0});
        items.push_back({KPItem::BOX, 3, 0, 0, 0, false, 0, 0, 0});
    }
    finish(items);
    KPLine out[8];
    for (int width : {8, 10}) {
        int n = kp_break_paragraph_spacing(items.data(), items.size(), width, width,
                                           KPSpacingParams(), out, 8);
        assert(n == 2 && out[0].break_item == 3);
        Metrics m = measure(items, 0, out[0].break_item, width);
        assert(m.feasible && m.badness == 100);
        assert(std::abs(std::abs(m.ratio) - 1.0 / 3) < 1e-12);
        assert(out[0].ratio_x1000 == (width == 8 ? -334 : 334));
        Metrics last = measure(items, 4, out[1].break_item, width);
        assert(last.ragged && last.feasible && !last.has_ratio && last.spaces == 0);
    }
    assert(kp_break_paragraph_spacing(items.data(), items.size(), 11, 11,
                                      KPSpacingParams(), out, 8) == -1);
    assert(!measure(items, 0, 3, 11).feasible);
    assert(std::isinf(measure(items, 0, 1, 10).ratio));
    assert(measure(items, 0, 1, 10).badness == KP_INFINITY);
    assert(measure(items, 0, 1, 3).ratio == 0);
    assert(measure(items, 0, 7, 14).ragged);
    assert(measure(items, 0, 7, 14).has_ratio);
    std::cerr << "kp-benchmark selfcheck passed\n";
}

static void number(double value) {
    if (std::isfinite(value)) std::cout << value;
    else std::cout << "null";
}

int main(int argc, char** argv) try {
    if (argc == 2 && std::string(argv[1]) == "--selfcheck") {
        selfcheck();
        return 0;
    }
    if (argc != 7)
        throw std::runtime_error("usage: kp-benchmark FONT SIZE MIN_WIDTH MAX_WIDTH STEP REPEATS < paragraphs.txt");
    int size = std::stoi(argv[2]), low = std::stoi(argv[3]), high = std::stoi(argv[4]);
    int step = std::stoi(argv[5]), repeats = std::stoi(argv[6]);
    if (size < 1 || size > 256 || low < 1 || high < low || high > 10000 || step < 1 || step > 10000
            || repeats < 1 || repeats > 100)
        throw std::runtime_error("invalid size, width range or repeat count");
    FT_Library library;
    FT_Face face;
    if (FT_Init_FreeType(&library) || FT_New_Face(library, argv[1], 0, &face)
            || FT_Set_Pixel_Sizes(face, 0, size))
        throw std::runtime_error("cannot initialise font");
    hb_font_t* font = hb_ft_font_create_referenced(face);
    hb_buffer_t* buffer = hb_buffer_create();
    auto advance = [&](const std::string& word) {
        hb_buffer_clear_contents(buffer);
        hb_buffer_add_utf8(buffer, word.data(), word.size(), 0, word.size());
        hb_buffer_guess_segment_properties(buffer);
        if (hb_buffer_get_direction(buffer) != HB_DIRECTION_LTR)
            throw std::runtime_error("adapter supports LTR text only");
        hb_shape(font, buffer, nullptr, 0);
        unsigned count;
        auto info = hb_buffer_get_glyph_infos(buffer, &count);
        auto positions = hb_buffer_get_glyph_positions(buffer, &count);
        long long total = 0;
        for (unsigned i = 0; i < count; ++i) {
            if (info[i].codepoint == 0) throw std::runtime_error("font is missing a glyph");
            total += positions[i].x_advance;
        }
        if (total < 0 || total > 64000000) throw std::runtime_error("unsupported advance");
        return static_cast<int>((total + 32) / 64);
    };
    int space = advance(" ");
    if (!space) throw std::runtime_error("zero-width space at this font size");
    std::cout << std::setprecision(12);
    std::string text;
    int paragraph = 0;
    while (std::getline(std::cin, text)) {
        if (text.size() > 100000) throw std::runtime_error("paragraph exceeds 100000 bytes");
        std::istringstream words(text);
        std::string word;
        std::vector<KPItem> items;
        int word_count = 0;
        try {
            while (words >> word) {
                if (word_count++) items.push_back({KPItem::GLUE, space, space / 2,
                                                   space / 2, 0, false, 0, space, 0});
                items.push_back({KPItem::BOX, advance(word), 0, 0, 0, false, 0, 0, 0});
            }
        } catch (const std::runtime_error& error) {
            std::cout << "{\"paragraph\":" << paragraph++ << ",\"exclusion\":\"" << error.what() << "\"}\n";
            continue;
        }
        if (!word_count) throw std::runtime_error("empty input paragraph");
        finish(items);
        std::vector<KPLine> lines(items.size());
        for (int width = low; width <= high; width += step) {
            // Rotate algorithm order; timings exclude shaping, tracing and one warm-up.
            for (int order = 0; order < 3; ++order) {
                int algorithm = (order + paragraph + width) % 3;
                const char* name = algorithm == 0 ? "spacing" : algorithm == 1 ? "classical" : "greedy_model";
                auto solve = [&]() {
                    if (algorithm == 0)
                        return kp_break_paragraph_spacing(items.data(), items.size(), width, width,
                                                           KPSpacingParams(), lines.data(), lines.size());
                    if (algorithm == 1) {
                        KPParams params;
                        params.tolerance = 100;
                        return kp_break_paragraph(items.data(), items.size(), width, width,
                                                  params, lines.data(), lines.size());
                    }
                    int n = 0, natural = 0;
                    for (int i = 0; i < static_cast<int>(items.size()) - 3; i += 2) {
                        int next = items[i].width;
                        if (i && natural + space + next > width) {
                            lines[n++] = {i - 1, 0};
                            natural = next;
                        } else natural += (i ? space : 0) + next;
                    }
                    lines[n++] = {static_cast<int>(items.size()) - 1, 0};
                    return n;
                };
                int count = solve();
                auto selected = lines;
                std::vector<double> times;
                for (int repeat = 0; repeat < repeats; ++repeat) {
                    auto begin = std::chrono::steady_clock::now();
                    int again = solve();
                    auto end = std::chrono::steady_clock::now();
                    if (again != count) throw std::runtime_error("nondeterministic result");
                    for (int i = 0; i < count; ++i)
                        if (selected[i].break_item != lines[i].break_item
                                || selected[i].ratio_x1000 != lines[i].ratio_x1000)
                            throw std::runtime_error("nondeterministic path");
                    times.push_back(std::chrono::duration<double, std::micro>(end - begin).count());
                }
                std::cout << "{\"paragraph\":" << paragraph << ",\"width\":" << width
                          << ",\"algorithm\":\"" << name << "\",\"words\":" << word_count
                          << ",\"items\":" << items.size() << ",\"solve_samples_us\":[";
                for (std::size_t i = 0; i < times.size(); ++i) {
                    if (i) std::cout << ',';
                    std::cout << times[i];
                }
                std::cout << "],\"success\":" << (count >= 0 ? "true" : "false") << ",\"lines\":[";
                int start = 0;
                for (int i = 0; i < count; ++i) {
                    int end = lines[i].break_item;
                    Metrics m = measure(items, start, end, width);
                    if (algorithm == 0) {
                        int q = m.has_ratio && m.spaces ? static_cast<int>(
                            (std::abs(static_cast<long long>(width) - m.natural) * KP_RATIO_SCALE
                             + m.spaces - 1) / m.spaces) : 0;
                        if (m.ratio < 0) q = -q;
                        if (!m.feasible || q != lines[i].ratio_x1000)
                            throw std::runtime_error("score reconstruction mismatch");
                    }
                    if (i) std::cout << ',';
                    std::cout << "{\"break_item\":" << end << ",\"natural\":" << m.natural
                              << ",\"adjustable\":" << m.spaces << ",\"stretch\":" << m.stretch
                              << ",\"shrink\":" << m.shrink << ",\"ragged\":" << (m.ragged ? "true" : "false")
                              << ",\"feasible\":" << (m.feasible ? "true" : "false")
                              << ",\"has_ratio\":" << (m.has_ratio ? "true" : "false") << ",\"ratio\":";
                    number(m.ratio);
                    std::cout << ",\"capacity_ratio\":"; number(m.capacity_ratio);
                    std::cout << ",\"badness\":" << m.badness << ",\"solver_ratio_x1000\":";
                    if (algorithm == 2) std::cout << "null";
                    else std::cout << lines[i].ratio_x1000;
                    std::cout << '}';
                    start = end + 1;
                }
                std::cout << "]}\n";
            }
        }
        ++paragraph;
    }
    hb_buffer_destroy(buffer);
    hb_font_destroy(font);
    FT_Done_Face(face);
    FT_Done_FreeType(library);
} catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
