--[==[
    ╔═══════════════════════════════════════╗
    ║   DALEY HUB  -  Black & Red UI Lib    ║
    ╚═══════════════════════════════════════╝

    USAGE:
        local Daley = loadstring(readfile("DaleyHub.lua"))()   -- or host it and use game:HttpGet
        local Window = Daley:CreateWindow({ Name = "Daley Hub" })

        local Tab = Window:CreateTab("Main")
        Tab:AddSection("Combat")
        Tab:AddButton({ Name = "Run Script", Callback = function() print("hi") end })
        Tab:AddToggle({ Name = "Auto Farm", Flag = "AutoFarm", Callback = function(v) print(v) end })
        Tab:AddSlider({ Name = "Speed", Min = 0, Max = 100, Default = 16, Callback = function(v) end })
        Tab:AddDropdown({ Name = "Mode", Options = {"A","B","C"}, Callback = function(v) end })
        Tab:AddTextbox({ Name = "Target", Placeholder = "name...", Callback = function(t) end })
        Tab:AddKeybind({ Name = "Fire", Default = Enum.KeyCode.E, Callback = function() end })
        Tab:AddLabel("Some text")

        Window:Notify({ Title = "Daley Hub", Text = "Loaded!", Duration = 4 })

    AUTO-EXECUTE ON SERVER HOP / TELEPORT:
        Requires an executor supporting queue_on_teleport.
        Pass the full hub loader (including all scripts) as AutoExecute:
        Daley:CreateWindow({
            Name = "Daley Hub",
            AutoExecute = [[ loadstring(game:HttpGet("https://your-host/DaleyHub_loader.lua"))() ]],
        })
        For Arise Shadows the complete script embeds this library and
        supplies its own self-contained loader; no hosting is required.
        Daley.Flags.AutoFarm  -- read any flagged value anywhere
]==]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Stats            = game:GetService("Stats")
local VirtualUser      = game:GetService("VirtualUser")

local LP = Players.LocalPlayer

local BACKGROUND_URL = "https://i.pinimg.com/1200x/cb/77/51/cb7751db9a5830655d9bdfc11ceccf4f.jpg"

local Library = { Flags = {}, Connections = {}, Version = "1.0" }

local Theme = {
    Background = Color3.fromRGB(8, 8, 10),
    Element    = Color3.fromRGB(12, 12, 16),
    Red        = Color3.fromRGB(225, 25, 45),
    DarkRed    = Color3.fromRGB(110, 10, 22),
    Text       = Color3.fromRGB(240, 240, 240),
    SubText    = Color3.fromRGB(175, 175, 180),
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Library.Connections, c)
    return c
end

local function New(class, props, children)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = o end
    return o
end

local function Corner(r) return New("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end

local function Stroke(color, thickness, transparency)
    return New("UIStroke", {
        Color = color or Theme.Red,
        Thickness = thickness or 1,
        Transparency = transparency or 0.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function Tween(obj, props, t)
    TweenService:Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad), props):Play()
end

local function Fire(cb, ...)
    if not cb then return end
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(cb, table.unpack(args, 1, args.n))
        if not ok then warn("[Daley Hub] Callback error: " .. tostring(err)) end
    end)
end

local function IsPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function Text(parent, props)
    local base = {
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = parent,
    }
    for k, v in pairs(props) do base[k] = v end
    return New("TextLabel", base)
end

local function MakeDraggable(handle, target)
    local dragging, startPos, startInput
    Connect(handle.InputBegan, function(i)
        if IsPress(i) then
            dragging, startInput, startPos = true, i.Position, target.Position
        end
    end)
    Connect(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    Connect(UserInputService.InputEnded, function(i)
        if IsPress(i) then dragging = false end
    end)
end

local function LoadBackground(imageLabel, url)
    task.spawn(function()
        pcall(function()
            local req = request or http_request or (syn and syn.request)
            if not (writefile and getcustomasset and req) then return end
            local file = "DaleyHub_bg.jpg"
            if not (isfile and isfile(file)) then
                local res = req({ Url = url, Method = "GET" })
                if not res or not res.Body or #res.Body < 1000 then return end
                writefile(file, res.Body)
            end
            imageLabel.Image = getcustomasset(file)
        end)
    end)
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
function Library:CreateWindow(cfg)
    cfg = cfg or {}
    local name      = cfg.Name or "Daley Hub"
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift
    local bgUrl     = cfg.Background or BACKGROUND_URL

    -- remove old copies
    pcall(function()
        for _, p in ipairs({ (gethui and gethui()) or game:GetService("CoreGui"), LP:FindFirstChild("PlayerGui") }) do
            local old = p and p:FindFirstChild("DaleyHub")
            if old then old:Destroy() end
        end
    end)

    local gui = New("ScreenGui", {
        Name = "DaleyHub", ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    })
    pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

    local Window = { Tabs = {}, Gui = gui, Current = nil, UserPicked = false, Visible = true, ToggleKey = toggleKey }

    -- Main frame
    local Main = New("Frame", {
        Name = "Main", Size = UDim2.fromOffset(700, 450), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Theme.Background,
        ClipsDescendants = true, Parent = gui,
    }, { Corner(10), Stroke(Theme.Red, 1.5, 0.15) })

    -- auto-scale so the UI fits small screens / phones
    local uiScale = New("UIScale", { Parent = Main })
    local function updateScale()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local vp = cam.ViewportSize
        uiScale.Scale = math.clamp(math.min(vp.X / 760, vp.Y / 500), 0.55, 1)
    end
    updateScale()
    if workspace.CurrentCamera then
        Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateScale)
    end

    local Bg = New("ImageLabel", {
        Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.1, ZIndex = 1, Parent = Main,
    }, { Corner(10) })
    -- fallback red/black gradient while (or if) the image can't load
    New("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(30, 0, 5), Color3.fromRGB(5, 5, 8)),
        Rotation = 45, Parent = Main,
    })
    LoadBackground(Bg, bgUrl)

    local Overlay = New("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5, ZIndex = 2, Parent = Main,
    }, { Corner(10) })

    -- Title bar
    local TitleBar = New("Frame", {
        Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.35, ZIndex = 3, Parent = Main,
    })
    New("Frame", { -- red line under title
        Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = Theme.Red, BorderSizePixel = 0, Parent = TitleBar,
    })
    local first, rest = name:match("^(%S+)%s*(.*)$")
    Text(TitleBar, {
        Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(14, 0),
        Font = Enum.Font.GothamBlack, TextSize = 19, RichText = true,
        Text = string.format('<font color="rgb(225,25,45)">%s</font> %s', (first or name):upper(), (rest or ""):upper()),
    })

    local function TitleButton(txt, xOff, color)
        local b = New("TextButton", {
            Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, xOff, 0.5, -11),
            BackgroundColor3 = color, BackgroundTransparency = 0.3, Text = txt,
            Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Theme.Text,
            AutoButtonColor = false, Parent = TitleBar,
        }, { Corner(5) })
        Connect(b.MouseEnter, function() Tween(b, { BackgroundTransparency = 0 }) end)
        Connect(b.MouseLeave, function() Tween(b, { BackgroundTransparency = 0.3 }) end)
        return b
    end
    local CloseBtn = TitleButton("X", -34, Theme.Red)
    local MinBtn   = TitleButton("–", -66, Theme.DarkRed)
    MakeDraggable(TitleBar, Main)

    -- Sidebar
    local Sidebar = New("Frame", {
        Size = UDim2.new(0, 160, 1, -38), Position = UDim2.fromOffset(0, 38),
        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 3, Parent = Main,
    })
    local TabHolder = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -24), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Red,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = Sidebar,
    }, {
        New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
        New("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
    })
    Text(Sidebar, {
        Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -22),
        Text = "v" .. Library.Version .. "  •  " .. toggleKey.Name .. " to hide",
        TextSize = 11, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
    })

    -- Content
    local Content = New("Frame", {
        Size = UDim2.new(1, -170, 1, -46), Position = UDim2.fromOffset(164, 42),
        BackgroundTransparency = 1, ZIndex = 3, Parent = Main,
    })

    -- minimize / close / toggle
    local minimized = false
    Connect(MinBtn.MouseButton1Click, function()
        minimized = not minimized
        Sidebar.Visible, Content.Visible = not minimized, not minimized
        Tween(Main, { Size = minimized and UDim2.fromOffset(700, 38) or UDim2.fromOffset(700, 450) }, 0.2)
    end)

    function Window:Toggle(v)
        if v == nil then v = not Window.Visible end
        Window.Visible = v
        Main.Visible = v
    end

    function Window:Destroy()
        for _, c in ipairs(Library.Connections) do pcall(function() c:Disconnect() end) end
        table.clear(Library.Connections)
        if Library.Cleanup then for _, fn in ipairs(Library.Cleanup) do pcall(fn) end end
        gui:Destroy()
    end
    Connect(CloseBtn.MouseButton1Click, function() Window:Destroy() end)

    Connect(UserInputService.InputBegan, function(i, gpe)
        if not gpe and i.KeyCode == Window.ToggleKey then Window:Toggle() end
    end)

    function Window:SetBackground(url) LoadBackground(Bg, url) end
    function Window:SetBackgroundTransparency(a) Bg.ImageTransparency = a end

    -- Notifications
    local NotifHolder = New("Frame", {
        Size = UDim2.new(0, 260, 1, -20), Position = UDim2.new(1, -270, 0, 10),
        BackgroundTransparency = 1, Parent = gui,
    }, { New("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right }) })

    function Window:Notify(o)
        o = o or {}
        local card = New("Frame", {
            Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.1,
            ClipsDescendants = true, Parent = NotifHolder,
        }, { Corner(8), Stroke(Theme.Red, 1, 0.2) })
        New("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Theme.Red, BorderSizePixel = 0, Parent = card })
        Text(card, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(12, 6), Text = o.Title or name, Font = Enum.Font.GothamBold, TextColor3 = Theme.Red })
        Text(card, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 24), Text = o.Text or "", TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, TextColor3 = Theme.SubText })
        Tween(card, { Size = UDim2.new(1, 0, 0, 62) }, 0.2)
        task.delay(o.Duration or 4, function()
            if card.Parent then
                Tween(card, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
                task.wait(0.25)
                card:Destroy()
            end
        end)
    end

    -----------------------------------------------------------------
    -- Tabs
    -----------------------------------------------------------------
    local function SelectTab(tab)
        for _, t in ipairs(Window.Tabs) do
            local active = (t == tab)
            t.Page.Visible = active
            Tween(t.Button, { BackgroundTransparency = active and 0.15 or 0.6, BackgroundColor3 = active and Theme.DarkRed or Theme.Element })
            t.Indicator.Visible = active
            t.Button.TextColor3 = active and Color3.new(1, 1, 1) or Theme.SubText
        end
        Window.Current = tab
    end

    function Window:CreateTab(tabName, opts)
        opts = opts or {}
        local Tab = { Name = tabName, IsSettings = opts.Settings, Window = Window }

        Tab.Button = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Element, BackgroundTransparency = 0.6,
            Text = tabName, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            AutoButtonColor = false, LayoutOrder = opts.Settings and 9999 or #Window.Tabs, Parent = TabHolder,
        }, { Corner(6), New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 8) }) })
        Tab.Indicator = New("Frame", {
            Size = UDim2.new(0, 3, 0.6, 0), Position = UDim2.new(0, -11, 0.2, 0),
            BackgroundColor3 = Theme.Red, BorderSizePixel = 0, Visible = false, Parent = Tab.Button,
        }, { Corner(2) })

        Tab.Page = New("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
            ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Red,
            AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = Content,
        }, {
            New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
            New("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
        })

        table.insert(Window.Tabs, Tab)
        Connect(Tab.Button.MouseButton1Click, function()
            Window.UserPicked = true
            SelectTab(Tab)
        end)
        Connect(Tab.Button.MouseEnter, function()
            if Window.Current ~= Tab then Tween(Tab.Button, { BackgroundTransparency = 0.35 }) end
        end)
        Connect(Tab.Button.MouseLeave, function()
            if Window.Current ~= Tab then Tween(Tab.Button, { BackgroundTransparency = 0.6 }) end
        end)

        if not Window.Current or (Window.Current.IsSettings and not Window.UserPicked and not Tab.IsSettings) then
            SelectTab(Tab)
        end

        local page = Tab.Page

        local function Base(h)
            local f = New("Frame", {
                Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Element,
                BackgroundTransparency = 0.25, Parent = page,
            }, { Corner(6), Stroke(Theme.Red, 1, 0.65) })
            return f
        end

        -- name (+ optional small description under it)
        local function Header(f, o, rightPad)
            local lbl = Text(f, {
                Size = UDim2.new(1, -rightPad, 1, 0), Position = UDim2.fromOffset(12, 0),
                Text = o.Name or "", TextSize = 14,
            })
            if o.Description then
                f.Size = UDim2.new(1, 0, 0, 54)
                lbl.Size = UDim2.new(1, -rightPad, 0, 30)
                lbl.Position = UDim2.fromOffset(12, 3)
                Text(f, {
                    Size = UDim2.new(1, -rightPad, 0, 16), Position = UDim2.fromOffset(12, 30),
                    Text = o.Description, TextSize = 12, TextColor3 = Theme.SubText, Font = Enum.Font.Gotham,
                })
            end
            return lbl
        end

        function Tab:AddSection(txt)
            local f = New("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = page })
            Text(f, { Size = UDim2.new(0, 0, 1, -4), AutomaticSize = Enum.AutomaticSize.X, Text = txt:upper(), Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = Theme.Red })
            local line = New("Frame", {
                Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -3),
                BackgroundColor3 = Theme.Red, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = f,
            })
            return f
        end

        function Tab:AddLabel(txt)
            local f = Base(32)
            local l = Text(f, { Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Text = txt, TextColor3 = Theme.SubText, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
            return { Set = function(_, t) l.Text = t end }
        end

        function Tab:AddButton(o)
            local f = Base(38)
            local b = New("TextButton", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = f,
            })
            Header(f, o, 44)
            Text(f, { Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -30, 0, 0), Text = "▶", TextColor3 = Theme.Red, TextSize = 12 })
            Connect(b.MouseEnter, function() Tween(f, { BackgroundColor3 = Theme.DarkRed }) end)
            Connect(b.MouseLeave, function() Tween(f, { BackgroundColor3 = Theme.Element }) end)
            Connect(b.MouseButton1Click, function()
                Tween(f, { BackgroundColor3 = Theme.Red }, 0.08)
                task.delay(0.1, function() Tween(f, { BackgroundColor3 = Theme.DarkRed }) end)
                Fire(o.Callback)
            end)
        end

        function Tab:AddToggle(o)
            local state = false
            local f = Base(38)
            Header(f, o, 70)
            local pill = New("Frame", {
                Size = UDim2.fromOffset(38, 18), Position = UDim2.new(1, -48, 0.5, -9),
                BackgroundColor3 = Color3.fromRGB(35, 35, 40), Parent = f,
            }, { Corner(9) })
            local knob = New("Frame", {
                Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(2, 2),
                BackgroundColor3 = Theme.Text, Parent = pill,
            }, { Corner(7) })
            local btn = New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = f })

            local obj = {}
            local function set(v, silent)
                state = v and true or false
                if o.Flag then Library.Flags[o.Flag] = state end
                Tween(pill, { BackgroundColor3 = state and Theme.Red or Color3.fromRGB(35, 35, 40) })
                Tween(knob, { Position = state and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2) })
                if not silent then Fire(o.Callback, state) end
            end
            Connect(btn.MouseButton1Click, function() set(not state) end)
            function obj:Set(v, silent) set(v, silent) end
            function obj:Get() return state end
            set(o.Default or false, not o.Default)
            return obj
        end

        function Tab:AddSlider(o)
            local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
            local value = math.clamp(o.Default or min, min, max)
            local f = Base(54)
            Text(f, { Size = UDim2.new(1, -90, 0, 22), Position = UDim2.fromOffset(12, 6), Text = o.Name or "Slider" })
            local val = Text(f, { Size = UDim2.fromOffset(70, 22), Position = UDim2.new(1, -82, 0, 6), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Red, Font = Enum.Font.GothamBold })
            local bar = New("Frame", {
                Size = UDim2.new(1, -24, 0, 6), Position = UDim2.fromOffset(12, 36),
                BackgroundColor3 = Color3.fromRGB(35, 35, 40), Parent = f,
            }, { Corner(3) })
            local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Red, Parent = bar }, { Corner(3) })

            local obj = {}
            local function set(v, silent)
                v = math.clamp(math.floor(v / inc + 0.5) * inc, min, max)
                v = tonumber(string.format("%.3f", v))
                value = v
                fill.Size = UDim2.fromScale((v - min) / math.max(max - min, 1e-9), 1)
                val.Text = tostring(v) .. (o.Suffix or "")
                if o.Flag then Library.Flags[o.Flag] = v end
                if not silent then Fire(o.Callback, v) end
            end
            local dragging = false
            local function fromX(x) set(min + (max - min) * math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)) end
            Connect(bar.InputBegan, function(i) if IsPress(i) then dragging = true fromX(i.Position.X) end end)
            Connect(f.InputBegan, function(i) if IsPress(i) and i.Position.Y > bar.AbsolutePosition.Y - 8 then dragging = true fromX(i.Position.X) end end)
            Connect(UserInputService.InputChanged, function(i)
                if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromX(i.Position.X) end
            end)
            Connect(UserInputService.InputEnded, function(i) if IsPress(i) then dragging = false end end)
            function obj:Set(v, silent) set(v, silent) end
            function obj:Get() return value end
            set(value, true)
            return obj
        end

        function Tab:AddDropdown(o)
            local options = o.Options or {}
            local selected = o.Default
            local open = false
            local f = Base(38)
            f.ClipsDescendants = true
            local head = Text(f, { Size = UDim2.new(1, -40, 0, 38), Position = UDim2.fromOffset(12, 0) })
            local arrow = Text(f, { Size = UDim2.fromOffset(24, 38), Position = UDim2.new(1, -28, 0, 0), Text = "▼", TextColor3 = Theme.Red, TextSize = 11 })
            local headBtn = New("TextButton", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Text = "", Parent = f })
            local list = New("ScrollingFrame", {
                Size = UDim2.new(1, -12, 0, 0), Position = UDim2.fromOffset(6, 42), BackgroundTransparency = 1,
                BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Red,
                AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = f,
            }, { New("UIListLayout", { Padding = UDim.new(0, 3) }) })

            local obj = {}
            local function refreshHead()
                head.Text = (o.Name or "Dropdown") .. (selected ~= nil and (":  " .. tostring(selected)) or "")
            end
            local function resize()
                local h = math.min(#options * 28, 140)
                Tween(f, { Size = UDim2.new(1, 0, 0, open and (38 + 8 + h) or 38) })
                list.Size = UDim2.new(1, -12, 0, h)
                arrow.Text = open and "▲" or "▼"
            end
            local function set(v, silent)
                selected = v
                if o.Flag then Library.Flags[o.Flag] = v end
                refreshHead()
                if not silent then Fire(o.Callback, v) end
            end
            local function build()
                for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
                for _, opt in ipairs(options) do
                    local b = New("TextButton", {
                        Size = UDim2.new(1, -4, 0, 25), BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.3,
                        Text = tostring(opt), Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Theme.Text,
                        AutoButtonColor = false, Parent = list,
                    }, { Corner(5) })
                    Connect(b.MouseEnter, function() Tween(b, { BackgroundColor3 = Theme.DarkRed, BackgroundTransparency = 0 }) end)
                    Connect(b.MouseLeave, function() Tween(b, { BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.3 }) end)
                    Connect(b.MouseButton1Click, function() set(opt) open = false resize() end)
                end
                resize()
            end
            Connect(headBtn.MouseButton1Click, function() open = not open resize() end)
            function obj:Set(v, silent) set(v, silent) end
            function obj:Get() return selected end
            function obj:SetOptions(t) options = t build() end
            build()
            refreshHead()
            if selected ~= nil and o.Flag then Library.Flags[o.Flag] = selected end
            return obj
        end

        function Tab:AddTextbox(o)
            local f = Base(38)
            Text(f, { Size = UDim2.new(0.5, -12, 1, 0), Position = UDim2.fromOffset(12, 0), Text = o.Name or "Textbox" })
            local box = New("TextBox", {
                Size = UDim2.new(0.5, -16, 0, 24), Position = UDim2.new(0.5, 6, 0.5, -12),
                BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.2, Text = o.Default or "",
                PlaceholderText = o.Placeholder or "...", PlaceholderColor3 = Theme.SubText, TextColor3 = Theme.Text,
                Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false, Parent = f,
            }, { Corner(5), Stroke(Theme.Red, 1, 0.6) })
            Connect(box.FocusLost, function(enter)
                if o.Flag then Library.Flags[o.Flag] = box.Text end
                Fire(o.Callback, box.Text, enter)
            end)
            return { Set = function(_, t) box.Text = t end, Get = function() return box.Text end }
        end

        function Tab:AddKeybind(o)
            local key = o.Default or Enum.KeyCode.Unknown
            local listening = false
            local f = Base(38)
            Text(f, { Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(12, 0), Text = o.Name or "Keybind" })
            local b = New("TextButton", {
                Size = UDim2.fromOffset(80, 24), Position = UDim2.new(1, -90, 0.5, -12),
                BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.2, Text = key.Name,
                Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Theme.Red, AutoButtonColor = false, Parent = f,
            }, { Corner(5), Stroke(Theme.Red, 1, 0.6) })
            local obj = {}
            local function set(k)
                key = k
                b.Text = k.Name
                if o.Flag then Library.Flags[o.Flag] = k end
                if o.OnChanged then Fire(o.OnChanged, k) end
            end
            Connect(b.MouseButton1Click, function() listening = true b.Text = "..." end)
            Connect(UserInputService.InputBegan, function(i, gpe)
                if listening and i.UserInputType == Enum.UserInputType.Keyboard then
                    listening = false
                    set(i.KeyCode == Enum.KeyCode.Escape and Enum.KeyCode.Unknown or i.KeyCode)
                elseif not gpe and not listening and key ~= Enum.KeyCode.Unknown and i.KeyCode == key then
                    Fire(o.Callback, key)
                end
            end)
            function obj:Set(k) set(k) end
            function obj:Get() return key end
            if o.Flag then Library.Flags[o.Flag] = key end
            return obj
        end

        return Tab
    end

    -----------------------------------------------------------------
    -- Built-in Settings tab
    -----------------------------------------------------------------
    if cfg.Settings ~= false then
        Library.Cleanup = Library.Cleanup or {}
        local S = Window:CreateTab("Settings", { Settings = true })

        local function Hum()
            local c = LP.Character
            return c and c:FindFirstChildOfClass("Humanoid")
        end

        ------------------------------------------------ AUTO EXECUTE (teleport / server hop)
        -- The caller provides the script to re-run. This is not a Roblox-native
        -- feature; it only works if the current executor exposes queue_on_teleport.
        local queueFn = queue_on_teleport or (syn and syn.queue_on_teleport)
            or (fluxus and fluxus.queue_on_teleport)
        local autoExec, queued = cfg.AutoExecuteEnabled ~= false, false

        local function AutoExecuteSource()
            local src = cfg.AutoExecute
            if (type(src) ~= "string" or src == "") and getgenv then
                local g = getgenv()
                src = g.ARISE_SHADOWS_AUTOEXEC
            end
            return type(src) == "string" and src ~= "" and src or nil
        end

        local function QueueExec()
            if not autoExec then return false end
            if queued then return true end
            if type(queueFn) ~= "function" then
                Window:Notify({ Title = "Auto Execute",
                    Text = "This executor does not support queue_on_teleport.", Duration = 5 })
                return false
            end
            local src = AutoExecuteSource()
            if not src then
                Window:Notify({ Title = "Auto Execute",
                    Text = "No reload source supplied. Execute the Arise Shadows file to enable full reloads.", Duration = 5 })
                return false
            end

            -- Capture the Arise settings before leaving; reload defaults are restored
            -- in the next server if this queued code actually runs.
            local g = (getgenv and getgenv()) or _G
            local stateCode = ""
            if type(g.ARISE_SHADOWS_GET_CONFIG) == "function" then
                local ok, snapshot = pcall(g.ARISE_SHADOWS_GET_CONFIG)
                if ok and type(snapshot) == "table" then
                    local encodedOk, json = pcall(HttpService.JSONEncode, HttpService, snapshot)
                    if encodedOk then
                        stateCode = "local g = (getgenv and getgenv()) or _G\n"
                            .. "g.ARISE_SHADOWS_RESTORE = game:GetService('HttpService'):JSONDecode("
                            .. string.format("%q", json) .. ")\n"
                    end
                end
            end
            local payload = "if not game:IsLoaded() then game.Loaded:Wait() end\n"
                .. stateCode .. src
            local ok = pcall(queueFn, payload)
            if not ok then
                Window:Notify({ Title = "Auto Execute",
                    Text = "Could not queue this script in the current executor.", Duration = 5 })
                return false
            end
            queued = true
            return true
        end

        Window.QueueAutoExecute = QueueExec
        -- also covers teleports started by the game itself
        Connect(LP.OnTeleport, function(state)
            if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then QueueExec() end
        end)

        ------------------------------------------------ MOVEMENT
        S:AddSection("Movement")

        local wsOn, wsVal = false, 16
        S:AddToggle({ Name = "WalkSpeed Boost", Callback = function(v)
            wsOn = v
            if not v and Hum() then Hum().WalkSpeed = 16 end
        end })
        S:AddSlider({ Name = "WalkSpeed Amount", Min = 16, Max = 250, Default = 16, Callback = function(v) wsVal = v end })

        local jpOn, jpVal = false, 50
        S:AddToggle({ Name = "JumpPower Boost", Callback = function(v)
            jpOn = v
            if not v and Hum() then Hum().UseJumpPower = true Hum().JumpPower = 50 end
        end })
        S:AddSlider({ Name = "JumpPower Amount", Min = 50, Max = 300, Default = 50, Callback = function(v) jpVal = v end })

        Connect(RunService.Heartbeat, function()
            local h = Hum()
            if not h then return end
            if wsOn then h.WalkSpeed = wsVal end
            if jpOn then h.UseJumpPower = true h.JumpPower = jpVal end
        end)

        S:AddToggle({ Name = "Infinite Jump", Callback = function(v) Library.Flags.InfJump = v end })
        Connect(UserInputService.JumpRequest, function()
            if Library.Flags.InfJump and Hum() then Hum():ChangeState(Enum.HumanoidStateType.Jumping) end
        end)

        local noclipConn
        S:AddToggle({ Name = "Noclip", Description = "Walk through walls", Callback = function(v)
            if v then
                noclipConn = RunService.Stepped:Connect(function()
                    local c = LP.Character
                    if c then
                        for _, p in ipairs(c:GetDescendants()) do
                            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
                        end
                    end
                end)
            elseif noclipConn then
                noclipConn:Disconnect() noclipConn = nil
            end
        end })
        table.insert(Library.Cleanup, function() if noclipConn then noclipConn:Disconnect() end end)

        ------------------------------------------------ FLY
        local flyOn, flySpeed = false, 60
        local flyBV, flyBG
        local function stopFly()
            if flyBV then flyBV:Destroy() flyBV = nil end
            if flyBG then flyBG:Destroy() flyBG = nil end
            local h = Hum()
            if h then h.PlatformStand = false end
        end
        local function startFly()
            stopFly()
            local c = LP.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            local h = Hum()
            if not (root and h) then return end
            flyBV = New("BodyVelocity", { MaxForce = Vector3.new(1e9, 1e9, 1e9), Velocity = Vector3.zero, Parent = root })
            flyBG = New("BodyGyro", { MaxTorque = Vector3.new(1e9, 1e9, 1e9), P = 9e4, CFrame = root.CFrame, Parent = root })
            h.PlatformStand = true
        end

        local flyToggle = S:AddToggle({
            Name = "Fly Mode",
            Description = "WASD / joystick to move, Space up, Shift down",
            Callback = function(v)
                flyOn = v
                if v then startFly() else stopFly() end
            end,
        })
        S:AddSlider({ Name = "Fly Speed", Min = 10, Max = 300, Default = 60, Callback = function(v) flySpeed = v end })
        S:AddKeybind({ Name = "Fly Toggle Key", Default = Enum.KeyCode.F, Callback = function()
            flyToggle:Set(not flyToggle:Get())
        end })

        Connect(RunService.RenderStepped, function()
            if not flyOn then return end
            local h, camera = Hum(), workspace.CurrentCamera
            local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not (h and root and camera) then return end
            if not (flyBV and flyBV.Parent and flyBG and flyBG.Parent) then startFly() if not flyBV then return end end

            local move = h.MoveDirection
            local look, right = camera.CFrame.LookVector, camera.CFrame.RightVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            flatLook = flatLook.Magnitude > 0 and flatLook.Unit or Vector3.zero
            local flatRight = Vector3.new(right.X, 0, right.Z)
            flatRight = flatRight.Magnitude > 0 and flatRight.Unit or Vector3.zero

            local fwd, side = move:Dot(flatLook), move:Dot(flatRight)
            local vel = look * fwd + right * side
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vel += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vel -= Vector3.yAxis end

            flyBV.Velocity = vel * flySpeed
            flyBG.CFrame = CFrame.new(root.Position, root.Position + look)
        end)
        table.insert(Library.Cleanup, function() flyOn = false stopFly() end)

        S:AddButton({ Name = "Reset Character", Callback = function()
            if Hum() then Hum().Health = 0 end
        end })

        ------------------------------------------------ UTILITY
        S:AddSection("Utility")

        local afkConn
        S:AddToggle({
            Name = "Auto Execute on Teleport",
            Description = "Reloads Arise Shadows + UI after server hop or rejoin",
            Default = autoExec,
            Callback = function(v)
                autoExec = v
                if v and (type(queueFn) ~= "function" or not AutoExecuteSource()) then
                    Window:Notify({
                        Title = "Auto Execute",
                        Text = type(queueFn) ~= "function" and "Executor has no queue_on_teleport."
                            or "No loader supplied. Run the Arise Shadows file first.",
                        Duration = 5,
                    })
                end
            end,
        })

        S:AddToggle({ Name = "Anti AFK", Description = "Stops Roblox from kicking you for idling", Default = true, Callback = function(v)
            if afkConn then afkConn:Disconnect() afkConn = nil end
            if v then
                afkConn = LP.Idled:Connect(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
                Window:Notify({ Title = "Anti AFK", Text = "Enabled - you won't be kicked for idling.", Duration = 3 })
            end
        end })
        table.insert(Library.Cleanup, function() if afkConn then afkConn:Disconnect() end end)

        ------------------------------------------------ VISUALS
        S:AddSection("Visuals")

        local origLight = {}
        local fbConn
        local function saveLight()
            origLight = {
                Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
                FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
        S:AddToggle({ Name = "Fullbright", Description = "Removes darkness and shadows", Callback = function(v)
            if v then
                saveLight()
                fbConn = RunService.RenderStepped:Connect(function()
                    Lighting.Brightness = 2
                    Lighting.ClockTime = 14
                    Lighting.GlobalShadows = false
                    Lighting.Ambient = Color3.fromRGB(178, 178, 178)
                    Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
                    Lighting.FogEnd = 1e6
                end)
            else
                if fbConn then fbConn:Disconnect() fbConn = nil end
                for k, val in pairs(origLight) do pcall(function() Lighting[k] = val end) end
            end
        end })
        table.insert(Library.Cleanup, function() if fbConn then fbConn:Disconnect() end end)

        local fogConn, fogOrig
        S:AddToggle({ Name = "No Fog", Description = "Clear view at any distance", Callback = function(v)
            if v then
                fogOrig = { Lighting.FogStart, Lighting.FogEnd }
                fogConn = RunService.RenderStepped:Connect(function()
                    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
                    local a = Lighting:FindFirstChildOfClass("Atmosphere")
                    if a then a.Density = 0 end
                end)
            else
                if fogConn then fogConn:Disconnect() fogConn = nil end
                if fogOrig then Lighting.FogStart, Lighting.FogEnd = fogOrig[1], fogOrig[2] end
            end
        end })
        table.insert(Library.Cleanup, function() if fogConn then fogConn:Disconnect() end end)

        local cam = workspace.CurrentCamera
        S:AddSlider({ Name = "Field of View", Min = 30, Max = 120, Default = math.floor(cam and cam.FieldOfView or 70), Callback = function(v)
            if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = v end
        end })

        ------------------------------------------------ PERFORMANCE
        S:AddSection("Performance")

        local statsLabel = S:AddLabel("FPS: --  |  Ping: -- ms")
        do
            local frames, last = 0, os.clock()
            Connect(RunService.RenderStepped, function()
                frames += 1
                local now = os.clock()
                if now - last >= 0.5 then
                    local fps = math.floor(frames / (now - last))
                    frames, last = 0, now
                    local ping = "--"
                    pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                    statsLabel:Set(("FPS: %s  |  Ping: %s ms"):format(fps, ping))
                end
            end)
        end

        S:AddButton({ Name = "Boost FPS", Description = "Removes textures, shadows & effects (rejoin to undo)", Callback = function()
            task.spawn(function()
                pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 9e9
                for _, e in ipairs(Lighting:GetChildren()) do
                    if e:IsA("PostEffect") or e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("Atmosphere") then
                        pcall(function() e.Enabled = false end)
                    end
                end
                pcall(function()
                    local t = workspace.Terrain
                    t.WaterWaveSize, t.WaterWaveSpeed, t.WaterReflectance, t.WaterTransparency = 0, 0, 0, 0
                end)
                local n = 0
                for _, v in ipairs(workspace:GetDescendants()) do
                    pcall(function()
                        if v:IsA("BasePart") then
                            v.Material = Enum.Material.SmoothPlastic
                            v.CastShadow = false
                            v.Reflectance = 0
                        elseif v:IsA("Decal") or v:IsA("Texture") then
                            v.Transparency = 1
                        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                            v.Enabled = false
                        end
                    end)
                    n += 1
                    if n % 500 == 0 then task.wait() end
                end
                Window:Notify({ Title = "Boost FPS", Text = "Graphics reduced. Rejoin to restore them.", Duration = 4 })
            end)
        end })

        local origQuality
        S:AddToggle({ Name = "Low Graphics Mode", Description = "Lower quality & shadows - can be turned off", Callback = function(v)
            pcall(function()
                if v then
                    origQuality = settings().Rendering.QualityLevel
                    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
                    Lighting.GlobalShadows = false
                else
                    settings().Rendering.QualityLevel = origQuality or Enum.QualityLevel.Automatic
                    Lighting.GlobalShadows = true
                end
            end)
        end })

        if setfpscap then
            S:AddSlider({ Name = "FPS Cap  (0 = unlimited)", Min = 0, Max = 360, Default = 60, Increment = 5, Callback = function(v)
                pcall(setfpscap, v)
            end })
        end

        ------------------------------------------------ SERVER
        S:AddSection("Server")

        S:AddButton({ Name = "Rejoin Server", Callback = function()
            -- Kick() would terminate the session before Teleport() can start.
            if autoExec then QueueExec() end
            local ok = pcall(function()
                if #Players:GetPlayers() > 1 then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
                else
                    TeleportService:Teleport(game.PlaceId, LP)
                end
            end)
            if not ok then
                Window:Notify({ Title = "Rejoin", Text = "Teleport request failed.", Duration = 4 })
            end
        end })

        S:AddButton({ Name = "Server Hop", Description = "Joins a different public server", Callback = function()
            local ok, res = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(
                    "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
            end)
            if ok and res and type(res.data) == "table" then
                for _, s in ipairs(res.data) do
                    if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
                        if autoExec then QueueExec() end
                        local tpOK = pcall(TeleportService.TeleportToPlaceInstance,
                            TeleportService, game.PlaceId, s.id, LP)
                        if not tpOK then
                            Window:Notify({ Title = "Server Hop", Text = "Teleport request failed.", Duration = 4 })
                        end
                        return
                    end
                end
            end
            Window:Notify({ Title = "Server Hop", Text = "No other servers found.", Duration = 3 })
        end })

        S:AddButton({ Name = "Copy Job ID", Callback = function()
            if setclipboard then setclipboard(game.JobId) Window:Notify({ Title = "Copied", Text = "Job ID copied to clipboard.", Duration = 2 }) end
        end })
        S:AddButton({ Name = "Copy Place ID", Callback = function()
            if setclipboard then setclipboard(tostring(game.PlaceId)) Window:Notify({ Title = "Copied", Text = "Place ID copied to clipboard.", Duration = 2 }) end
        end })

        ------------------------------------------------ UI
        S:AddSection("Interface")

        S:AddKeybind({ Name = "Toggle UI Key", Default = Window.ToggleKey, OnChanged = function(k)
            if k ~= Enum.KeyCode.Unknown then Window.ToggleKey = k end
        end })
        S:AddSlider({ Name = "Background Visibility", Min = 0, Max = 100, Default = 90, Suffix = "%", Callback = function(v)
            Window:SetBackgroundTransparency(1 - v / 100)
        end })
        S:AddSlider({ Name = "Background Darkness", Min = 0, Max = 90, Default = 50, Suffix = "%", Callback = function(v)
            Overlay.BackgroundTransparency = 1 - v / 100
        end })
        S:AddButton({ Name = "Unload Daley Hub", Callback = function() Window:Destroy() end })
    end

    Window:Notify({ Title = name, Text = "Loaded. Press " .. toggleKey.Name .. " to hide/show.", Duration = 4 })
    return Window
end

return Library
