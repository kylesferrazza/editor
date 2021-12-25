import std.stdio;
import std.array;
import std.algorithm;
import std.exception : enforce;
import std.typecons : Nullable, nullable;
import std.string;
import bindbc.sdl;
import bindbc.sdl.ttf;

class Window {
    SDL_Window* window;
    SDL_Renderer* renderer;
    int width = 1080;
    int height = 720;

    this() {
        window = SDL_CreateWindow("editor", SDL_WINDOWPOS_UNDEFINED,
                SDL_WINDOWPOS_UNDEFINED, width, height, SDL_WINDOW_RESIZABLE);
        enforce(window);
        renderer = SDL_CreateRenderer(window, -1, 0);
        enforce(renderer);
    }

    void resize(int width, int height) {
        this.width = width;
        this.height = height;
    }

    void clear(SDL_Color color) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, 255);
        SDL_RenderClear(renderer);
    }

    void blit(SDL_Texture* texture, int x, int y) {
        int w, h;
        SDL_QueryTexture(texture, null, null, &w, &h);
        SDL_Rect dst = SDL_Rect(x, y, w, h);
        enforce(SDL_RenderCopy(renderer, texture, null, &dst) == 0);
    }

    void redraw() {
        SDL_RenderPresent(renderer);
    }
}

class Buffer {
    string[] lines;

    this(string filename) {
        auto file = File(filename);
        lines = file.byLine().map!(x => x.idup).array;
    }

    Nullable!(char) get(int x, int y) {
        Nullable!char result;

        enforce(x >= 0 && y >= 0);
        if (y >= lines.length) {
            return result;
        }

        string line = lines[y];
        if (x >= line.length) {
            return result;
        }
        result = line[x];
        return result;
    }

    void insert(char c, int x, int y) {
        string s = [c];
        lines[y] = lines[y][0 .. x] ~ s ~ lines[y][x .. $];
    }

    int num_lines() {
        return cast(int) lines.length;
    }
}

SDL_Color grey = {38, 50, 56};
SDL_Color white = {205, 211, 222};

class Font {
    SDL_Renderer* renderer;
    TTF_Font* font;
    int width, height;

    struct ColoredGlyph {
        char c;
        SDL_Color fg, bg;
    }

    SDL_Texture*[ColoredGlyph] glyph_cache;

    this(SDL_Renderer* renderer, string font_path, int size) {
        this.renderer = renderer;
        font = TTF_OpenFont(toStringz(font_path), size);
        enforce(font);

        enforce(TTF_SizeText(font, " ", &width, &height) == 0);
    }

    SDL_Texture* render(char c, SDL_Color fg, SDL_Color bg) {
        ColoredGlyph colored_glyph = {c, fg, bg};
        if (colored_glyph in glyph_cache) {
            return glyph_cache[colored_glyph];
        }

        SDL_Surface* surface = TTF_RenderText_Shaded(font, toStringz([c]), fg, bg);
        enforce(surface);
        SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, surface);
        enforce(texture);
        SDL_FreeSurface(surface);

        glyph_cache[colored_glyph] = texture;

        return texture;
    }
}

struct Pos {
    int x, y;
};

class BufferView {
    Buffer buffer;
    Font font;
    int scroll_line;

    int cursor_line;
    int cursor_column;

    int rows;
    int columns;

    this(Buffer buffer, Font font) {
        this.buffer = buffer;
        this.font = font;
        scroll_line = 0;
        cursor_line = 0;
        cursor_column = 0;
    }

    void resize(int width, int height) {
        rows = height / font.height;
        columns = width / font.width;
        scroll();
    }

    void render(Window window) {
        foreach (screen_y; 0 .. rows) {
            foreach (screen_x; 0 .. columns) {
                int buffer_x = screen_x;
                int buffer_y = scroll_line + screen_y;
                Nullable!char c = buffer.get(buffer_x, buffer_y);

                bool is_cursor = buffer_x == cursor_column && buffer_y == cursor_line;

                if (c.isNull && is_cursor) {
                    auto text = font.render(' ', grey, white);
                    window.blit(text, screen_x * font.width, screen_y * font.height);
                } else if (!c.isNull) {
                    SDL_Color fg, bg;
                    if (is_cursor) {
                        fg = grey;
                        bg = white;
                    } else {
                        fg = white;
                        bg = grey;
                    }
                    auto text = font.render(c.get, fg, bg);
                    window.blit(text, screen_x * font.width, screen_y * font.height);
                }
            }
        }
    }

    void movex(int dx) {
        cursor_column += dx;
        if (cursor_column > columns) {
            cursor_column = columns;
        }
        if (cursor_column < 0) {
            cursor_column = 0;
        }

        scroll();
    }

    void movey(int dy) {
        cursor_line += dy;
        if (cursor_line < 0) {
            cursor_line = 0;
        }

        if (cursor_line > buffer.num_lines() - 1) {
            cursor_line = buffer.num_lines() - 1;
        }
        scroll();
    }

    void insert(char c) {
        buffer.insert(c, cursor_column, cursor_line);
        movex(1);
    }

    void movehalfpage(int dir) {
        int amount = dir * rows / 2;
        scroll_line += amount;
        movey(amount);
    }

    const int scrolloff = 2;
    void scroll() {
        if (cursor_line - scroll_line < scrolloff) {
            scroll_line = cursor_line - scrolloff;
        }
        if (cursor_line - scroll_line > rows - scrolloff) {
            scroll_line = cursor_line - rows + scrolloff;
        }
        if (scroll_line < 0) {
            scroll_line = 0;
        }
        if (scroll_line + rows > buffer.num_lines()) {
            scroll_line = buffer.num_lines() - rows;
        }
    }

}

void init_sdl() {
    enforce(loadSDL() == sdlSupport);
    enforce(loadSDLTTF() == sdlTTFSupport);

    enforce(SDL_Init(SDL_INIT_VIDEO) == 0);
    enforce(TTF_Init() == 0);

}

void main() {
    init_sdl();
    Window window = new Window();
    Buffer buffer = new Buffer("source/app.d");
    Font font = new Font(window.renderer, "fonts/PragmataPro Mono Regular.ttf", 16);
    BufferView buffer_view = new BufferView(buffer, font);
    window.clear(grey);
    bool running = true;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
            case SDL_QUIT:
                running = false;
                break;
            case SDL_WINDOWEVENT:
                switch (event.window.event) {
                case SDL_WINDOWEVENT_RESIZED:
                    int w = event.window.data1;
                    int h = event.window.data2;
                    window.resize(w, h);
                    buffer_view.resize(w, h);
                    break;
                default:
                    break;
                }
                break;
            case SDL_KEYDOWN:
                switch (event.key.keysym.sym) {
                case SDLK_h:
                    buffer_view.movex(-1);
                    break;
                case SDLK_j:
                    buffer_view.movey(1);
                    break;
                case SDLK_k:
                    buffer_view.movey(-1);
                    break;
                case SDLK_l:
                    buffer_view.movex(1);
                    break;
                case SDLK_f:
                    if (event.key.keysym.mod & KMOD_CTRL) {
                        buffer_view.movehalfpage(2);
                    } else {
                        buffer_view.insert('f');
                    }
                    break;
                case SDLK_b:
                    if (event.key.keysym.mod & KMOD_CTRL) {
                        buffer_view.movehalfpage(-2);
                    }
                    break;
                case SDLK_d:
                    if (event.key.keysym.mod & KMOD_CTRL) {
                        buffer_view.movehalfpage(1);
                    }
                    break;
                case SDLK_u:
                    if (event.key.keysym.mod & KMOD_CTRL) {
                        buffer_view.movehalfpage(-1);
                    }
                    break;
                default:
                    break;
                }
                break;
            default:
                break;
            }

        }
        window.clear(grey);
        buffer_view.render(window);

        window.redraw();
    }
}
