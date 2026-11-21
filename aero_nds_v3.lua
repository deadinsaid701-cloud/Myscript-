--[[
  Aero | Natural Disaster v3.0 (RU)  -  Delta (Luau, client-side)
  Всё выключено по умолчанию. Меню: RightShift (или круглая кнопка слева).
  Горячие клавиши (ПК): G управление | B вкладка «Рисунок» | V сформировать | F полёт | H ESP | M режим | E/Q вверх/вниз

  v3.0:
    * Фигура строится ПЕРЕД ИГРОКОМ (по горизонтальному направлению камеры), а не в позиции камеры.
      Ползунок «Расстояние» (Ближе <-> Дальше). Минимальная дистанция считается из радиуса щита и глубины фигуры.
    * Авто-размер: размер подбирается по FOV/пропорциям экрана, расстояние при необходимости увеличивается само.
    * Щит: предметы под контролем не могут войти в сферу вокруг персонажа (отталкивание + обход по касательной),
      цели фигуры никогда не лежат внутри щита -> рисунок остаётся стабильным.
    * 2 тестовые анимации из частиц (двойная спираль, пульсирующая сфера).
    * Интерфейс полностью на русском, числа заменены ползунками.
]]

local genv = (getgenv and getgenv()) or _G
if genv.__AeroNDS then
    pcall(genv.__AeroNDS.Destroy)
end

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer
if not LP then
    error("[Aero] LocalPlayer is nil - запусти скрипт внутри игры, а не в меню")
end

-- ===================== CONFIG (единое место) =====================
local CFG = {
    -- управление предметами
    ScanRadius   = math.huge, -- студы; math.huge = вся карта
    OrbitRadius  = 25,
    MaxPartSize  = 80,
    MaxParts     = 900,
    ScanInterval = 0.5,
    ScanBudget   = 1200,
    RequireOwner = true,
    PhaseThrough = true,
    Gain         = 6,
    FigGain      = 16,        -- жёсткость наведения на точки фигуры
    MaxSpeed     = 250,
    OrbitSpeed   = 1.2,
    -- фигура
    FigAuto      = true,      -- авто-размер
    FigSize      = 60,        -- ручной размер (длинная сторона, студы)
    FigMax       = 220,
    FigDist      = 55,        -- расстояние от игрока до фигуры (студы)
    FigHeight    = 0,         -- сдвиг по высоте
    FigLayers    = 3,
    FigFollow    = true,
    FigSmooth    = 10,        -- сглаживание поворота за камерой
    FigOverlap   = 0.9,
    FigOutlier   = 3,
    -- щит
    Shield       = true,
    ShieldRadius = 14,
    ShieldShow   = true,
    -- анимации
    AnimSpeed    = 1,
    AnimCount    = 300,
    -- полёт / esp
    FlySpeed     = 60,
    EspFill      = Color3.fromRGB(255, 60, 60),
    EspOutline   = Color3.fromRGB(255, 255, 255),
    EspInterval  = 0.1,
    Keys = {
        Menu  = Enum.KeyCode.RightShift,
        Fly   = Enum.KeyCode.F,
        Parts = Enum.KeyCode.G,
        Esp   = Enum.KeyCode.H,
        Mode  = Enum.KeyCode.M,
        Up    = Enum.KeyCode.E,
        Down  = Enum.KeyCode.Q,
        Draw  = Enum.KeyCode.B,
        Form  = Enum.KeyCode.V,
    },
}
local BRUSH = { { name = "Тонко", r = 2 }, { name = "Средне", r = 8 }, { name = "Толсто", r = 16 } }
-- ================================================================

local HAS_SIM   = type(sethiddenproperty) == "function"
local HAS_OWNER = type(isnetworkowner) == "function"

local MODES = {
    { id = "Orbit",  name = "Орбита",    desc = "Предметы летают кругами вокруг тебя." },
    { id = "Vortex", name = "Вихрь",     desc = "Предметы закручиваются воронкой вокруг тебя." },
    { id = "Magnet", name = "Магнит",    desc = "Предметы летят туда, куда смотрит камера." },
    { id = "Hold",   name = "Заморозка", desc = "Предметы зависают там, где они были." },
    { id = "Figure", name = "Рисунок",   desc = "Предметы выстроены в фигуру или анимацию перед тобой." },
}
local MODE_FIGURE = 5
local S = {
    Parts = false, Fly = false, Esp = false, Mode = 1, up = false, down = false,
    Brush = 2, Fill = false, Tab = 1, Anim = nil,
}

-- ============================ ТЕМА ==============================
local T = {
    bg    = Color3.fromRGB(13, 14, 21),
    panel = Color3.fromRGB(19, 21, 31),
    card  = Color3.fromRGB(26, 29, 43),
    cardHi= Color3.fromRGB(36, 40, 60),
    off   = Color3.fromRGB(50, 55, 80),
    stroke= Color3.fromRGB(55, 62, 92),
    text  = Color3.fromRGB(236, 238, 248),
    sub   = Color3.fromRGB(140, 148, 178),
    acc   = Color3.fromRGB(124, 92, 255),
    acc2  = Color3.fromRGB(0, 200, 255),
    ok    = Color3.fromRGB(60, 220, 150),
    warn  = Color3.fromRGB(255, 176, 70),
    bad   = Color3.fromRGB(255, 90, 110),
}
-- Source Sans гарантированно содержит кириллицу
local FONT = { reg = Enum.Font.SourceSans, med = Enum.Font.SourceSansSemibold, bold = Enum.Font.SourceSansBold }
local EASE = Enum.EasingStyle
local DOUT = Enum.EasingDirection.Out

local conns = {}
local function track(c)
    conns[#conns + 1] = c
    return c
end

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function tw(o, t, props, style, dir)
    local ok, tween = pcall(function()
        local tn = TweenService:Create(o, TweenInfo.new(t, style or EASE.Quad, dir or DOUT), props)
        tn:Play()
        return tn
    end)
    return ok and tween or nil
end

local up3, zero3 = Vector3.new(0, 1, 0), Vector3.new(0, 0, 0)

local function getChar()
    local c = LP.Character
    if not c then return nil end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then
        return c, hrp, hum
    end
    return nil
end

local function getCenter()
    local _, hrp = getChar()
    if hrp then return hrp.Position end
    local cam = Workspace.CurrentCamera
    if cam then return cam.CFrame.Position end
    return zero3
end

local function pickContainer()
    if type(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and typeof(h) == "Instance" then return h end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then
        local probe = Instance.new("Folder")
        local okp = pcall(function() probe.Parent = cg end)
        probe:Destroy()
        if okp then return cg end
    end
    return LP:WaitForChild("PlayerGui")
end
local CONTAINER = pickContainer()

local Destroy
local refresh, toast, setStats, replan, markDirty
local menuOpen = false
local ui = {}

-- ScreenGui создаётся рано: тосты нужны логике
local gui = mk("ScreenGui", {
    Name = "AeroNDS",
    ResetOnSpawn = false,
    IgnoreGuiInset = false, -- AbsolutePosition и InputObject.Position в одном пространстве (как в v2)
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, CONTAINER)

local orders = setmetatable({}, { __mode = "k" })
local function ord(p)
    local n = (orders[p] or 0) + 1
    orders[p] = n
    return n
end

-- ============================ ТОСТЫ =============================
local toastHolder = mk("Frame", {
    Name = "Toasts", Size = UDim2.new(0, 340, 0, 220), AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 12), BackgroundTransparency = 1, ZIndex = 50,
}, gui)
mk("UIListLayout", {
    Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
}, toastHolder)

toast = function(text, kind)
    local col = (kind == "bad" and T.bad) or (kind == "ok" and T.ok) or (kind == "warn" and T.warn) or T.acc
    local f = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = T.card, BackgroundTransparency = 1, BorderSizePixel = 0,
        LayoutOrder = ord(toastHolder), ZIndex = 51,
    }, toastHolder)
    mk("UICorner", { CornerRadius = UDim.new(0, 9) }, f)
    local st = mk("UIStroke", { Color = col, Thickness = 1.2, Transparency = 1 }, f)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, f)
    local sc = mk("UIScale", { Scale = 0.9 }, f)
    local l = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Text = text, TextColor3 = T.text, Font = FONT.med, TextSize = 16, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, ZIndex = 52,
    }, f)
    tw(f, 0.25, { BackgroundTransparency = 0.05 })
    tw(st, 0.25, { Transparency = 0.2 })
    tw(l, 0.25, { TextTransparency = 0 })
    tw(sc, 0.35, { Scale = 1 }, EASE.Back)
    task.delay(2.6, function()
        if not f.Parent then return end
        tw(f, 0.3, { BackgroundTransparency = 1 })
        tw(st, 0.3, { Transparency = 1 })
        tw(l, 0.3, { TextTransparency = 1 })
        task.delay(0.35, function() pcall(function() f:Destroy() end) end)
    end)
end

-- ============ ПЛАНИРОВЩИК (чистая математика, без Roblox API) ===
-- >>> PLANNER BEGIN
local Planner = {}
Planner.GRID = 96

function Planner.raster(strokes, canvas, fill)
    local G = Planner.GRID
    local floor, sqrt, max = math.floor, math.sqrt, math.max
    local cell = canvas / G
    local occ = {}
    for i = 1, G * G do occ[i] = false end

    local function stamp(x, y, r)
        local rr = max(r, cell * 0.75)
        local gx0 = clamp(floor((x - rr) / cell), 0, G - 1)
        local gx1 = clamp(floor((x + rr) / cell), 0, G - 1)
        local gy0 = clamp(floor((y - rr) / cell), 0, G - 1)
        local gy1 = clamp(floor((y + rr) / cell), 0, G - 1)
        local r2 = rr * rr
        for gy = gy0, gy1 do
            local dy = (gy + 0.5) * cell - y
            for gx = gx0, gx1 do
                local dx = (gx + 0.5) * cell - x
                if dx * dx + dy * dy <= r2 then occ[gy * G + gx + 1] = true end
            end
        end
    end

    for _, s in ipairs(strokes) do
        local pts = s.pts
        local n = #pts
        if n == 1 then
            stamp(pts[1].x, pts[1].y, s.r)
        else
            for i = 1, n - 1 do
                local a, b = pts[i], pts[i + 1]
                local dx, dy = b.x - a.x, b.y - a.y
                local len = sqrt(dx * dx + dy * dy)
                local steps = max(1, math.ceil(len / (cell * 0.5)))
                for k = 0, steps do
                    local t = k / steps
                    stamp(a.x + dx * t, a.y + dy * t, s.r)
                end
            end
        end
    end

    if fill then
        local outside, q, qh, qt = {}, {}, 1, 0
        local function push(gx, gy)
            if gx < 0 or gy < 0 or gx >= G or gy >= G then return end
            local i = gy * G + gx + 1
            if occ[i] or outside[i] then return end
            outside[i] = true
            qt = qt + 1
            q[qt] = i
        end
        for k = 0, G - 1 do
            push(k, 0); push(k, G - 1); push(0, k); push(G - 1, k)
        end
        while qh <= qt do
            local i = q[qh]
            qh = qh + 1
            local gx = (i - 1) % G
            local gy = floor((i - 1) / G)
            push(gx + 1, gy); push(gx - 1, gy); push(gx, gy + 1); push(gx, gy - 1)
        end
        for i = 1, G * G do
            if not outside[i] then occ[i] = true end
        end
    end

    local cells = {}
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for gy = 0, G - 1 do
        for gx = 0, G - 1 do
            if occ[gy * G + gx + 1] then
                cells[#cells + 1] = { gx = gx, gy = gy }
                if gx < minx then minx = gx end
                if gx > maxx then maxx = gx end
                if gy < miny then miny = gy end
                if gy > maxy then maxy = gy end
            end
        end
    end
    return cells, cell, { minx = minx, maxx = maxx, miny = miny, maxy = maxy }
end

local function blockCount(cells, f)
    local floor = math.floor
    local seen, n = {}, 0
    for i = 1, #cells do
        local c = cells[i]
        local key = floor(c.gx / f) * 1024 + floor(c.gy / f)
        if not seen[key] then
            seen[key] = true
            n = n + 1
        end
    end
    return n
end

function Planner.sample(cells, N)
    local floor = math.floor
    local f, guard = 1, 0
    while blockCount(cells, f) > N and guard < 400 do
        f = f * 1.03
        guard = guard + 1
    end
    local blocks, order = {}, {}
    for i = 1, #cells do
        local c = cells[i]
        local key = floor(c.gx / f) * 1024 + floor(c.gy / f)
        local b = blocks[key]
        if not b then
            b = { sx = 0, sy = 0, n = 0 }
            blocks[key] = b
            order[#order + 1] = b
        end
        b.sx = b.sx + c.gx + 0.5
        b.sy = b.sy + c.gy + 0.5
        b.n = b.n + 1
    end
    local pts = {}
    for i = 1, #order do
        local b = order[i]
        pts[i] = { gx = b.sx / b.n, gy = b.sy / b.n }
    end
    return pts, f
end

-- opts = { canvas, size, sizeFn(wPx,hPx)->size, maxSize, overlap, maxLayers, fill, rng }
function Planner.build(strokes, parts, opts)
    local floor, max = math.floor, math.max
    local N = #parts
    if N == 0 then return nil, "нет свободных предметов" end
    if #strokes == 0 then return nil, "нет штрихов" end
    local cells, cellPx, bb = Planner.raster(strokes, opts.canvas, opts.fill)
    if #cells == 0 then return nil, "пустой рисунок" end

    local pts, f = Planner.sample(cells, N)
    local P = #pts
    local layers = 1
    if f <= 1.0001 then layers = clamp(floor(N / P), 1, opts.maxLayers) end
    local total = P * layers

    local exts = {}
    for i = 1, N do exts[i] = parts[i].ext end
    table.sort(exts)
    local dMed = max(0.5, exts[floor((N + 1) / 2)])

    local wPx = (bb.maxx - bb.minx + 1) * cellPx
    local hPx = (bb.maxy - bb.miny + 1) * cellPx
    local cx = (bb.minx + bb.maxx + 1) * 0.5 * cellPx
    local cy = (bb.miny + bb.maxy + 1) * 0.5 * cellPx
    local bboxPx = max(wPx, hPx)
    local spacingPx = f * cellPx

    local size = opts.size
    if opts.sizeFn then size = opts.sizeFn(wPx, hPx) end
    local s = max(size / bboxPx, dMed * opts.overlap / spacingPx)
    local capped = false
    if bboxPx * s > opts.maxSize then
        s = opts.maxSize / bboxPx
        capped = true
    end
    local dz = max(1, dMed * opts.overlap)

    local order = {}
    for i = 1, N do order[i] = i end
    local rng = opts.rng
    for i = N, 2, -1 do
        local j = floor(rng() * i) + 1
        order[i], order[j] = order[j], order[i]
    end

    local slots, k = {}, 0
    for l = 1, layers do
        for p = 1, P do
            k = k + 1
            local px, py = pts[p].gx * cellPx, pts[p].gy * cellPx
            slots[k] = {
                px = px, py = py,
                x = (px - cx) * s, y = -(py - cy) * s, z = -(l - 1) * dz,
                layer = l, part = order[k],
            }
        end
    end
    local reserve = {}
    for i = total + 1, N do reserve[#reserve + 1] = order[i] end

    return {
        slots = slots, reserve = reserve, P = P, layers = layers, total = total,
        f = f, scale = s, capped = capped, dMed = dMed, cells = #cells, N = N, dz = dz,
        width = wPx * s, height = hPx * s, spacing = spacingPx * s,
        tight = spacingPx * s / dMed,
    }
end
-- <<< PLANNER END

-- ======================= ИНФО О ПРЕДМЕТАХ =======================
local GROUP = {
    Rock = "Камень", Slate = "Камень", Granite = "Камень", Basalt = "Камень", Cobblestone = "Камень",
    Pebble = "Камень", Limestone = "Камень", Sandstone = "Камень", Marble = "Камень",
    Wood = "Дерево", WoodPlanks = "Дерево",
    Metal = "Металл", CorrodedMetal = "Металл", DiamondPlate = "Металл", Foil = "Металл",
    Plastic = "Пластик", SmoothPlastic = "Пластик",
    Grass = "Трава", LeafyGrass = "Трава", Ground = "Земля", Mud = "Земля",
}

local infoCache = setmetatable({}, { __mode = "k" })

local function extentOf(root)
    local sz = root.Size
    local e = math.max(sz.X, sz.Y, sz.Z)
    local ok, conn = pcall(root.GetConnectedParts, root, true)
    if ok and type(conn) == "table" and #conn > 1 then
        local mnx, mny, mnz = math.huge, math.huge, math.huge
        local mxx, mxy, mxz = -math.huge, -math.huge, -math.huge
        for i = 1, math.min(#conn, 40) do
            local q = conn[i]
            local pos, r = q.Position, q.Size.Magnitude * 0.5
            mnx = math.min(mnx, pos.X - r); mxx = math.max(mxx, pos.X + r)
            mny = math.min(mny, pos.Y - r); mxy = math.max(mxy, pos.Y + r)
            mnz = math.min(mnz, pos.Z - r); mxz = math.max(mxz, pos.Z + r)
        end
        e = math.max(e, mxx - mnx, mxy - mny, mxz - mnz)
    end
    return e
end

local function getInfo(root)
    local i = infoCache[root]
    if i then return i end
    local shape = "Other"
    if root:IsA("Part") then
        local ok, nm = pcall(function() return root.Shape.Name end)
        shape = ok and nm or "Block"
    elseif root:IsA("MeshPart") then
        shape = "Mesh"
    end
    local mat = root.Material.Name
    i = { root = root, ext = extentOf(root), color = root.Color, group = GROUP[mat] or mat, shape = shape }
    infoCache[root] = i
    return i
end

local function newWeak() return setmetatable({}, { __mode = "k" }) end
local phase, lift, heldPos = newWeak(), newWeak(), newWeak()
local function resetHeld() heldPos = newWeak() end

local fig = nil              -- активная формация (рисунок или анимация)
local held = {}
local candidates, candMap, candTotal = {}, {}, 0
local onScanDone = nil
local shieldHits, shieldHitsShown = 0, 0

-- ===================== УПРАВЛЕНИЕ ПРЕДМЕТАМИ ====================
local function boostSim()
    if HAS_SIM then pcall(sethiddenproperty, LP, "SimulationRadius", 1e9) end
    pcall(function() LP.MaximumSimulationRadius = 1e9 end)
end

local function acquire(root)
    local list = {}
    local ok, conn = pcall(root.GetConnectedParts, root, true)
    if not ok or type(conn) ~= "table" or #conn == 0 then conn = { root } end
    for i = 1, math.min(#conn, 40) do
        local q = conn[i]
        if q.CanCollide then
            q.CanCollide = false
            list[#list + 1] = q
        end
    end
    held[root] = list
end

local function release(root)
    local list = held[root]
    held[root] = nil
    if list then
        for _, q in ipairs(list) do
            pcall(function() q.CanCollide = true end)
        end
    end
end

local function releaseAll()
    for root in pairs(held) do release(root) end
end

local function syncHeld()
    if not (S.Parts and CFG.PhaseThrough) then
        releaseAll()
        return
    end
    for root in pairs(held) do
        local rec = candMap[root]
        if (not rec) or (not rec.own) or (not root.Parent) then release(root) end
    end
    for i = 1, #candidates do
        local rec = candidates[i]
        if rec.own and rec.root.Parent and not held[rec.root] then acquire(rec.root) end
    end
end

local function maintainSlots()
    local f = fig
    if not f then return end
    for k, root in pairs(f.slotRoot) do
        local rec = candMap[root]
        if (not root.Parent) or root.Anchored then
            f.slotRoot[k] = nil; f.slotOf[root] = nil; f.miss[k] = nil
        elseif (not rec) or (not rec.own) then
            local m = (f.miss[k] or 0) + 1
            f.miss[k] = m
            if m >= 6 then
                f.slotRoot[k] = nil; f.slotOf[root] = nil; f.miss[k] = nil
            end
        else
            f.miss[k] = nil
        end
    end
    local ci = 1
    for k = 1, f.n do
        if not f.slotRoot[k] then
            while ci <= #candidates do
                local rec = candidates[ci]
                ci = ci + 1
                if rec.own and not f.slotOf[rec.root] then
                    f.slotRoot[k] = rec.root
                    f.slotOf[rec.root] = k
                    break
                end
            end
        end
    end
end

-- ---- сканер: весь Workspace, по кускам ----
local known = {}
for _, d in ipairs(Workspace:GetDescendants()) do
    if d:IsA("BasePart") then known[d] = true end
end
track(Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("BasePart") then known[d] = true end
end))
track(Workspace.DescendantRemoving:Connect(function(d)
    known[d] = nil
end))

local scan = { list = nil, i = 1, seen = nil, out = nil, center = nil, last = 0 }

local function blockedByAncestor(root)
    local cam = Workspace.CurrentCamera
    local a, depth = root.Parent, 0
    while a and a ~= Workspace and depth < 12 do
        if a == cam then return true end
        if a:FindFirstChildOfClass("Humanoid") then return true end
        a = a.Parent
        depth = depth + 1
    end
    return false
end

local function scanBegin(center)
    local list, n = {}, 0
    for p in pairs(known) do
        n = n + 1
        list[n] = p
    end
    scan.list, scan.i, scan.seen, scan.out, scan.center = list, 1, {}, {}, center
    if S.Parts then boostSim() end
end

local function scanFinish(silent)
    local out = scan.out
    table.sort(out, function(a, b)
        if a.own ~= b.own then return a.own end
        return a.d < b.d
    end)
    candTotal = #out
    local capped = out
    if #out > CFG.MaxParts then
        capped = {}
        for i = 1, CFG.MaxParts do capped[i] = out[i] end
    end
    candidates = capped
    candMap = {}
    for i = 1, #capped do candMap[capped[i].root] = capped[i] end
    scan.list, scan.seen, scan.out = nil, nil, nil
    scan.last = os.clock()
    syncHeld()
    maintainSlots()
    if onScanDone and not silent then onScanDone() end
end

local function scanStep(budget, silent)
    local list = scan.list
    if not list then return true end
    local n = #list
    local stop = math.min(n, scan.i + budget - 1)
    local seen, out, center = scan.seen, scan.out, scan.center
    local R, maxSz = CFG.ScanRadius, CFG.MaxPartSize
    for i = scan.i, stop do
        local p = list[i]
        if p.Parent and not p.Anchored then
            local root = p.AssemblyRootPart
            if root and not seen[root] then
                seen[root] = true
                if root.Parent and not root.Anchored and root.Size.Magnitude <= maxSz and not blockedByAncestor(root) then
                    local d = (root.Position - center).Magnitude
                    if d <= R then
                        local own = true
                        if HAS_OWNER and CFG.RequireOwner then
                            local ok, v = pcall(isnetworkowner, root)
                            if ok then own = v and true or false end
                        end
                        out[#out + 1] = { root = root, d = d, own = own }
                    end
                end
            end
        end
    end
    scan.i = stop + 1
    if scan.i > n then
        scanFinish(silent)
        return true
    end
    return false
end

local function scanSync(silent)
    scanBegin(getCenter())
    scanStep(math.huge, silent)
end

local function wantScan()
    return S.Parts or (menuOpen and (S.Tab == 2 or S.Tab == 3 or S.Tab == 4))
end

local function scanTick()
    if not wantScan() then return end
    if scan.list then
        scanStep(CFG.ScanBudget)
    else
        local every = S.Parts and CFG.ScanInterval or 1.5
        if os.clock() - scan.last >= every then
            scanBegin(getCenter())
            scanStep(CFG.ScanBudget)
        end
    end
end

-- ===================== ГЕОМЕТРИЯ ФОРМАЦИИ =======================
-- размеры видимой области на расстоянии d
local function viewDims(d)
    local cam = Workspace.CurrentCamera
    local fov = math.rad(cam and cam.FieldOfView or 70)
    local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local H = 2 * d * math.tan(fov * 0.5)
    return H, H * vs.X / math.max(vs.Y, 1)
end

-- минимальная дистанция до центра формации: щит + глубина в сторону игрока + запас
local function shieldFloor(depth, rad)
    return (CFG.Shield and CFG.ShieldRadius or 6) + depth + (rad or 0) + 6
end

-- максимальные высота/ширина фигуры, при которых она целиком в кадре на дистанции d
local function autoFit(d)
    local H, W = viewDims(d)
    return H * 0.45 + 4, W * 0.7
end

-- итоговая дистанция (учёт щита и авто-подгонки под кадр)
local function planDistance(w, h, depth, rad)
    local d = math.max(CFG.FigDist, shieldFloor(depth, rad))
    if CFG.FigAuto then
        local H1, W1 = viewDims(1)
        d = math.max(d, (h - 4) / (0.45 * H1), w / (0.7 * W1))
    end
    return math.min(d, 400)
end

-- положение формации: перед ИГРОКОМ по горизонтальному направлению камеры
local function targetCF(f)
    local cam = Workspace.CurrentCamera
    local _, hrp = getChar()
    if not (cam and hrp) then return f.cf end
    local cf = cam.CFrame
    local look = cf.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.05 then
        local u = cf.UpVector
        flat = Vector3.new(u.X, 0, u.Z)
        if look.Y > 0 then flat = -flat end
        if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
    end
    flat = flat.Unit
    local right = flat:Cross(up3)
    local p = hrp.Position
    -- центр на уровне глаз + сдвиг, но низ формации не уходит под землю
    local cy = math.max(p.Y + 2 + CFG.FigHeight, p.Y - 1 + f.height * 0.5)
    return CFrame.fromMatrix(Vector3.new(p.X, cy, p.Z) + flat * f.distEff, right, up3)
end

local function updateFormation(dt)
    local f = fig
    if not f then return end
    local tgt = targetCF(f)
    if CFG.FigFollow then
        if not f.cf then
            f.cf = tgt
            f.vel = zero3
        else
            local a = 1 - math.exp(-dt * CFG.FigSmooth)
            local old = f.cf.Position
            f.cf = f.cf:Lerp(tgt, a)
            local v = (f.cf.Position - old) / math.max(dt, 1e-3)
            if v.Magnitude > 150 then v = v.Unit * 150 end
            f.vel = v
        end
    else
        if f.repin or not f.cf then
            f.cf = tgt
            f.repin = false
        end
        f.vel = zero3
    end
    if f.kind == "anim" then f.phase = f.phase + dt * CFG.AnimSpeed end
end

-- ===================== ЩИТ (физика) =============================
local function pushOut(goal, c, r)
    local rel = goal - c
    local d = rel.Magnitude
    if d >= r then return goal end
    if d < 1e-3 then return c + up3 * r end
    return c + rel.Unit * r
end

-- убирает из скорости составляющую «внутрь» сферы, скользит по касательной, выталкивает изнутри
local function shieldAdjust(pos, v, c, cv, rs, dt)
    local rel = pos - c
    local d = rel.Magnitude
    local vr = v - cv
    local lookahead = (rel + vr * dt * 2).Magnitude
    local edge = rs * 1.15
    if d >= edge and lookahead >= edge then return v end
    shieldHits = shieldHits + 1
    local n = d > 1e-3 and rel / d or up3
    local sp = vr.Magnitude
    local inward = vr:Dot(n)
    if inward < 0 then vr = vr - n * inward end
    if sp > 1 then
        local tang = vr - n * vr:Dot(n)
        if tang.Magnitude < sp * 0.35 then
            local side = n:Cross(up3)
            if side.Magnitude < 0.1 then side = n:Cross(Vector3.new(1, 0, 0)) end
            vr = vr + side.Unit * sp * 0.6
        end
    end
    if d < rs then
        vr = vr + n * ((rs - d) * 14 + 25)
    end
    return vr + cv
end

local function radOf(rec)
    local r = rec.rad
    if not r then
        r = math.min(getInfo(rec.root).ext * 0.5, 30)
        rec.rad = r
    end
    return r
end

local SPIN = Vector3.new(0, 3, 0)

local function stepParts(t, dt)
    local _, hrp = getChar()
    if not hrp then return end

    local cam = Workspace.CurrentCamera
    local base = hrp.Position
    local cvel = hrp.AssemblyLinearVelocity
    local shieldOn = CFG.Shield
    local rs0 = CFG.ShieldRadius
    local mode = MODES[S.Mode].id
    if mode == "Figure" and not fig then mode = "Orbit" end
    local R = CFG.OrbitRadius
    if shieldOn then R = math.max(R, rs0 + 6) end
    local magnet = nil
    if mode == "Magnet" and cam then
        magnet = cam.CFrame.Position + cam.CFrame.LookVector * math.max(40, rs0 + 20)
    end
    local fcf, fvel = nil, nil
    if mode == "Figure" then
        updateFormation(dt)
        fcf, fvel = fig.cf, fig.vel or zero3
    end
    local gcomp = Vector3.new(0, Workspace.Gravity * dt, 0)
    local invdt = 0.8 / math.max(dt, 1e-3)
    local g, gf = math.min(CFG.Gain, invdt), math.min(CFG.FigGain, invdt)

    for i = 1, #candidates do
        local rec = candidates[i]
        local root = rec.root
        if rec.own and root.Parent and not root.Anchored then
            local goal, still, gain, ff = nil, false, g, zero3
            local slot = fcf and fig.slotOf[root]
            if slot then
                local lp = fig.fn and fig.fn(slot, fig.phase) or fig.loc[slot]
                goal = fcf:PointToWorldSpace(lp)
                still, gain, ff = true, gf, fvel
            else
                local ph = phase[root]
                if not ph then
                    ph = math.random() * math.pi * 2
                    phase[root] = ph
                    lift[root] = math.random()
                end
                local lf = lift[root]
                if mode == "Orbit" or mode == "Figure" then
                    local a = ph + t * CFG.OrbitSpeed
                    goal = base + Vector3.new(math.cos(a) * R, 3 + (lf - 0.5) * 8, math.sin(a) * R)
                elseif mode == "Vortex" then
                    local a = ph + t * CFG.OrbitSpeed * (1.6 - lf)
                    local r = R * (0.3 + 0.7 * lf)
                    goal = base + Vector3.new(math.cos(a) * r, 2 + lf * 35, math.sin(a) * r)
                elseif mode == "Magnet" then
                    if magnet then
                        goal = magnet + Vector3.new(math.cos(ph * 3) * 8 * lf, math.sin(ph * 5) * 8, math.sin(ph * 7) * 8 * lf)
                    end
                else -- Hold
                    local h = heldPos[root]
                    if not h then
                        h = root.Position
                        heldPos[root] = h
                    end
                    goal = h
                    still = true
                end
                if goal and shieldOn then goal = pushOut(goal, base, rs0 + 3) end
            end

            if goal then
                local pos = root.Position
                local v = (goal - pos) * gain + gcomp + ff
                local m = v.Magnitude
                if m > CFG.MaxSpeed then v = v * (CFG.MaxSpeed / m) end
                if shieldOn then
                    v = shieldAdjust(pos, v, base, cvel, rs0 + radOf(rec), dt)
                    m = v.Magnitude
                    if m > CFG.MaxSpeed then v = v * (CFG.MaxSpeed / m) end
                end
                root.AssemblyLinearVelocity = v
                root.AssemblyAngularVelocity = still and zero3 or SPIN
            end
        end
    end
end

-- ===================== ВИЗУАЛ ЩИТА ===============================
local shieldPart, shieldVis = nil, 0
local function stepShield(t, dt)
    local _, hrp = getChar()
    local show = S.Parts and CFG.Shield and CFG.ShieldShow and hrp ~= nil
    shieldVis = shieldVis + ((show and 1 or 0) - shieldVis) * math.min(1, dt * 7)
    if shieldVis < 0.01 and not show then
        if shieldPart then
            pcall(function() shieldPart:Destroy() end)
            shieldPart = nil
        end
        return
    end
    if not hrp then return end
    if not shieldPart or not shieldPart.Parent then
        shieldPart = mk("Part", {
            Name = "AeroShield", Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false,
            CanTouch = false, CanQuery = false, CastShadow = false, Locked = true,
            Material = Enum.Material.ForceField, Color = T.acc2, Transparency = 1,
        }, Workspace.CurrentCamera or Workspace)
    end
    local d = CFG.ShieldRadius * 2
    shieldPart.Size = Vector3.new(d, d, d)
    shieldPart.CFrame = hrp.CFrame
    shieldPart.Transparency = 1 - shieldVis * (0.2 + 0.06 * math.sin(t * 3))
end

-- ============================ ПОЛЁТ =============================
local flyAtt, flyLV, flyAO

local function flyOff()
    for _, o in ipairs({ flyLV, flyAO, flyAtt }) do
        if o then pcall(function() o:Destroy() end) end
    end
    flyLV, flyAO, flyAtt = nil, nil, nil
end

local function flyOn()
    local _, hrp = getChar()
    if not hrp then return end
    flyOff()
    flyAtt = mk("Attachment", { Name = "AeroFlyAtt" }, hrp)
    flyLV = mk("LinearVelocity", {
        Attachment0 = flyAtt,
        VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        MaxForce = math.huge,
        VectorVelocity = zero3,
    }, hrp)
    flyAO = mk("AlignOrientation", {
        Mode = Enum.OrientationAlignmentMode.OneAttachment,
        Attachment0 = flyAtt,
        RigidityEnabled = false,
        MaxTorque = math.huge,
        Responsiveness = 40,
        CFrame = hrp.CFrame.Rotation,
    }, hrp)
end

local function stepFly()
    local _, hrp, hum = getChar()
    if not hrp then return end
    if not (flyLV and flyLV.Parent == hrp) then flyOn() end
    if not flyLV then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local v = zero3
    local md = hum.MoveDirection
    if md.Magnitude > 0.01 then
        local lv = cam.CFrame:VectorToObjectSpace(md)
        local flat = Vector3.new(lv.X, 0, lv.Z)
        if flat.Magnitude > 0.001 then
            v = cam.CFrame:VectorToWorldSpace(flat.Unit * md.Magnitude)
        end
    end
    local upv = (S.up and 1 or 0) - (S.down and 1 or 0)
    flyLV.VectorVelocity = v * CFG.FlySpeed + Vector3.new(0, upv * CFG.FlySpeed, 0)

    local look = cam.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude > 0.01 and flyAO then
        flyAO.CFrame = CFrame.lookAt(zero3, flatLook)
    end
end

-- ============================ ESP ===============================
local espFolder = mk("Folder", { Name = "AeroESP" }, CONTAINER)
local espData = {}

local function espRemove(plr)
    local d = espData[plr]
    if d then
        pcall(function() d.hl:Destroy() end)
        pcall(function() d.bb:Destroy() end)
        espData[plr] = nil
    end
end

local function espClear()
    for plr in pairs(espData) do espRemove(plr) end
end

local function espAdd(plr, char, hrp)
    espRemove(plr)
    local hl = mk("Highlight", {
        Adornee = char, FillColor = CFG.EspFill, FillTransparency = 0.6,
        OutlineColor = CFG.EspOutline, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, espFolder)
    local bb = mk("BillboardGui", {
        Adornee = hrp, AlwaysOnTop = true, Size = UDim2.fromOffset(170, 38), StudsOffset = Vector3.new(0, 3.5, 0),
    }, espFolder)
    local lbl = mk("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextColor3 = T.text,
        TextStrokeTransparency = 0.4, Font = FONT.med, TextSize = 15, Text = plr.DisplayName,
    }, bb)
    espData[plr] = { hl = hl, bb = bb, label = lbl, char = char }
end

local function espUpdate()
    local _, myHrp = getChar()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = espData[plr]
                if (not d) or d.char ~= char then
                    espAdd(plr, char, hrp)
                    d = espData[plr]
                end
                if d then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local hp = hum and math.floor(hum.Health) or 0
                    local dist = myHrp and math.floor((hrp.Position - myHrp.Position).Magnitude) or 0
                    d.label.Text = string.format("%s\n%d м | %d HP", plr.DisplayName, dist, hp)
                end
            else
                espRemove(plr)
            end
        end
    end
end

-- ========================= ПЕРЕКЛЮЧАТЕЛИ ========================
local function stopAnim()
    S.Anim = nil
end

local function setParts(v)
    S.Parts = v
    if v then
        boostSim()
        scan.last = 0
        syncHeld()
        toast("Управление предметами включено", "ok")
    else
        releaseAll()
        fig = nil
        stopAnim()
        if MODES[S.Mode].id == "Figure" then S.Mode = 1 end
        resetHeld()
        toast("Управление предметами выключено", "warn")
    end
    refresh()
end

local function setFly(v)
    S.Fly = v
    if v then
        flyOn()
    else
        S.up, S.down = false, false
        flyOff()
    end
    refresh()
end

local function setEsp(v)
    S.Esp = v
    if not v then espClear() end
    refresh()
end

local function nextMode()
    local n = #MODES
    for _ = 1, n do
        S.Mode = S.Mode % n + 1
        if MODES[S.Mode].id ~= "Figure" or fig then break end
    end
    resetHeld()
    refresh()
end

local function releaseFigure()
    fig = nil
    stopAnim()
    if MODES[S.Mode].id == "Figure" then S.Mode = 1 end
    resetHeld()
    refresh()
end

-- ===================== РИСУНОК: ПЛАН ИЗ ПРЕДМЕТОВ ===============
local CANVAS = 240
local TRAIL = Color3.fromRGB(110, 140, 255)
local MINSEG = 3
local strokes = {}
local plan = nil
local dots = {}
local lastPlanN = -1
local drawing, curStroke, drawInput = false, nil, nil

local function buildPlan()
    local infos = {}
    for i = 1, #candidates do
        local root = candidates[i].root
        if root.Parent and not root.Anchored then
            infos[#infos + 1] = getInfo(root)
        end
    end
    if #infos == 0 then return nil, "свободные предметы не найдены (нажми «Поиск»)" end
    local exts = {}
    for i = 1, #infos do exts[i] = infos[i].ext end
    table.sort(exts)
    local med = exts[math.floor((#exts + 1) / 2)]
    local limit = math.max(med * CFG.FigOutlier, med + 4)
    local fit = {}
    for i = 1, #infos do
        if infos[i].ext <= limit then fit[#fit + 1] = infos[i] end
    end

    local maxRad = math.min(limit * 0.5, 30)
    local sizeFn = nil
    if CFG.FigAuto then
        local depthEst = (CFG.FigLayers - 1) * math.max(1, med * CFG.FigOverlap)
        local d0 = math.max(CFG.FigDist, shieldFloor(depthEst, maxRad))
        local hf, wf = autoFit(d0)
        sizeFn = function(wPx, hPx)
            local L = math.max(wPx, hPx, 1)
            return math.min(hf * L / math.max(hPx, 1), wf * L / math.max(wPx, 1))
        end
    end

    local rnd = Random.new(1337)
    local p, err = Planner.build(strokes, fit, {
        canvas = CANVAS, size = CFG.FigSize, sizeFn = sizeFn, maxSize = CFG.FigMax,
        overlap = CFG.FigOverlap, maxLayers = CFG.FigLayers, fill = S.Fill,
        rng = function() return rnd:NextNumber() end,
    })
    if not p then return nil, err end
    p.fit = fit
    p.outliers = #infos - #fit
    p.depth = (p.layers - 1) * p.dz
    p.rad = maxRad
    p.distEff = planDistance(p.width, p.height, p.depth, maxRad)
    return p
end

local function legendOf(p)
    local by, order = {}, {}
    for _, s in ipairs(p.slots) do
        local info = p.fit[s.part]
        local e = by[info.group]
        if not e then
            e = { n = 0, r = 0, g = 0, b = 0 }
            by[info.group] = e
            order[#order + 1] = info.group
        end
        e.n = e.n + 1
        e.r = e.r + info.color.R
        e.g = e.g + info.color.G
        e.b = e.b + info.color.B
    end
    table.sort(order, function(a, b) return by[a].n > by[b].n end)
    local out = {}
    for i = 1, math.min(#order, 6) do
        local gname = order[i]
        local e = by[gname]
        local hex = Color3.new(e.r / e.n, e.g / e.n, e.b / e.n):ToHex()
        out[#out + 1] = string.format('<font color="#%s">■</font> %s x%d', hex, gname, e.n)
    end
    return table.concat(out, "   ")
end

local function planText(p)
    local l = {}
    l[#l + 1] = string.format("Свободных предметов: %d (лимит %d)", candTotal, CFG.MaxParts)
    l[#l + 1] = string.format("Использовано %d | в запасе %d | слоёв x%d", p.total, #p.reserve, p.layers)
    l[#l + 1] = string.format("Фигура %d x %d студов, дистанция %d", math.floor(p.width + 0.5), math.floor(p.height + 0.5), math.floor(p.distEff + 0.5))
    if p.f > 1.0001 then
        l[#l + 1] = string.format("Предметов мало для полной детализации: %d точек из %d", p.P, p.cells)
    end
    if p.capped then l[#l + 1] = "Размер ограничен: предметы перекрываются" end
    if p.outliers > 0 then l[#l + 1] = string.format("%d слишком больших предметов остаются в орбите", p.outliers) end
    l[#l + 1] = legendOf(p)
    return table.concat(l, "\n")
end

local function applyPlan(p)
    local f = {
        kind = "draw", slotRoot = {}, slotOf = {}, loc = {}, miss = {}, n = #p.slots,
        cf = nil, vel = zero3, depth = p.depth, height = p.height, distEff = p.distEff, rad = p.rad,
    }
    for k, s in ipairs(p.slots) do
        local root = p.fit[s.part].root
        f.loc[k] = Vector3.new(s.x, s.y, s.z)
        f.slotRoot[k] = root
        f.slotOf[root] = k
    end
    f.cf = targetCF(f)
    fig = f
end

local function formFigure()
    if #strokes == 0 then
        toast("Сначала нарисуй фигуру во вкладке «Рисунок»", "warn")
        return
    end
    if not getChar() then
        toast("Нет живого персонажа", "bad")
        return
    end
    stopAnim()
    if not S.Parts then S.Parts = true; boostSim() end
    scanSync(true)
    local p, err = buildPlan()
    if not p then
        toast("Не получилось: " .. tostring(err), "bad")
        return
    end
    plan = p
    applyPlan(p)
    S.Mode = MODE_FIGURE
    resetHeld()
    syncHeld()
    toast("Фигура сформирована — предметы летят на место", "ok")
    refresh()
    if replan then replan() end
end

-- ===================== ТЕСТОВЫЕ АНИМАЦИИ ========================
local ANIMS = {
    { id = "helix",  name = "Двойная спираль",     desc = "Две спирали из частиц вращаются перед тобой, как ДНК." },
    { id = "sphere", name = "Пульсирующая сфера",  desc = "Шар из частиц медленно вращается и «дышит»." },
}

-- возвращает fn(k, phase) -> Vector3 (x вправо, y вверх, z к игроку), глубину и высоту
local function animShape(id, n, size)
    if id == "helix" then
        local H, R = size, size * 0.2
        local m = math.max(1, math.floor(n / 2))
        local pi2 = math.pi * 2
        local fn = function(k, ph)
            local strand = k % 2
            local u = math.min(1, ((k - strand) / 2) / math.max(m - 1, 1))
            local a = u * 3 * pi2 + ph * 1.6 + strand * math.pi
            return Vector3.new(math.cos(a) * R, (u - 0.5) * H, math.sin(a) * R)
        end
        return fn, R, H
    end
    -- sphere
    local R = size / (2 * 1.18)
    local ga = math.pi * (1 + math.sqrt(5))
    local fn = function(k, ph)
        local i = k - 0.5
        local phi = math.acos(1 - 2 * i / n)
        local th = ga * i
        local sp = math.sin(phi)
        local x, y, z = sp * math.cos(th), math.cos(phi), sp * math.sin(th)
        local c, s = math.cos(ph * 0.7), math.sin(ph * 0.7)
        local rx, rz = x * c + z * s, -x * s + z * c
        local r = R * (1 + 0.18 * math.sin(ph * 2.2))
        return Vector3.new(rx * r, y * r, rz * r)
    end
    return fn, R * 1.18, size
end

local function animGeometry(id, n, rad)
    local d0 = math.max(CFG.FigDist, shieldFloor(0, rad))
    local size
    if CFG.FigAuto then
        local hf, wf = autoFit(d0)
        size = math.min(hf, wf)
    else
        size = CFG.FigSize
    end
    size = clamp(size, 10, CFG.FigMax)
    local fn, depth, height = animShape(id, n, size)
    return fn, depth, height, planDistance(size, height, depth, rad)
end

local function startAnim(id)
    if not getChar() then
        toast("Нет живого персонажа", "bad")
        return
    end
    if not S.Parts then S.Parts = true; boostSim() end
    scanSync(true)
    local infos = {}
    for i = 1, #candidates do
        if candidates[i].own and candidates[i].root.Parent then infos[#infos + 1] = getInfo(candidates[i].root) end
    end
    local owned, maxRad = {}, 0
    if #infos > 0 then
        local exts = {}
        for i = 1, #infos do exts[i] = infos[i].ext end
        table.sort(exts)
        local med = exts[math.floor((#exts + 1) / 2)]
        local limit = math.max(med * CFG.FigOutlier, med + 4)
        for i = 1, #infos do
            if infos[i].ext <= limit then
                owned[#owned + 1] = infos[i].root
                maxRad = math.max(maxRad, math.min(infos[i].ext * 0.5, 30))
            end
        end
    end
    local n = math.min(math.floor(CFG.AnimCount), #owned)
    if n < 12 then
        toast(string.format("Мало свободных предметов под контролем: %d", #owned), "bad")
        return
    end
    local fn, depth, height, dist = animGeometry(id, n, maxRad)
    local f = {
        kind = "anim", id = id, fn = fn, slotRoot = {}, slotOf = {}, miss = {}, n = n, phase = 0,
        cf = nil, vel = zero3, depth = depth, height = height, distEff = dist, rad = maxRad,
    }
    for k = 1, n do
        f.slotRoot[k] = owned[k]
        f.slotOf[owned[k]] = k
    end
    f.cf = targetCF(f)
    fig = f
    S.Anim = id
    S.Mode = MODE_FIGURE
    resetHeld()
    syncHeld()
    toast("Анимация запущена: " .. (id == "helix" and "двойная спираль" or "пульсирующая сфера"), "ok")
    refresh()
end

-- ===================== ПЕРЕСБОРКА ПРИ СМЕНЕ НАСТРОЕК ============
local dirty, dirtyAt = nil, 0
markDirty = function(kind)
    dirty = (dirty == "anim" or kind == "anim") and "anim" or kind
    dirtyAt = os.clock()
end

local function refit()
    local f = fig
    if not f then return end
    if f.kind == "draw" then
        local p = buildPlan()
        if not p then return end
        plan = p
        if #p.slots == f.n then
            for k, s in ipairs(p.slots) do f.loc[k] = Vector3.new(s.x, s.y, s.z) end
            f.depth, f.height, f.distEff = p.depth, p.height, p.distEff
            if not CFG.FigFollow then f.repin = true end
        else
            applyPlan(p)
        end
    else
        local fn, depth, height, dist = animGeometry(f.id, f.n, f.rad)
        f.fn, f.depth, f.height, f.distEff = fn, depth, height, dist
        if not CFG.FigFollow then f.repin = true end
    end
end

local function applyDirty(kind)
    if #strokes > 0 and replan then replan() end
    if not fig then return end
    if kind == "anim" and fig.kind == "anim" then
        startAnim(fig.id)
    else
        refit()
    end
end

-- ===================== UI: ПРИМИТИВЫ ============================
local painters = {}
local function paint(fn)
    painters[#painters + 1] = fn
    pcall(fn, true)
end
refresh = function()
    for i = 1, #painters do pcall(painters[i], false) end
end

local scrollers = {}
local function lockScroll(v)
    for _, s in ipairs(scrollers) do s.ScrollingEnabled = not v end
end

local function isPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function corner(o, r)
    return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function label(parent, text, size, color, font, props)
    local l = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Text = text, TextSize = size, TextColor3 = color, Font = font, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = ord(parent),
    }, parent)
    if props then
        for k, v in pairs(props) do l[k] = v end
    end
    return l
end

local function section(parent, text)
    local l = label(parent, text, 15, T.acc2, FONT.bold)
    mk("UIPadding", { PaddingTop = UDim.new(0, 4) }, l)
    return l
end

local function card(parent)
    local f = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = T.card, BorderSizePixel = 0, LayoutOrder = ord(parent),
    }, parent)
    corner(f, 10)
    mk("UIStroke", { Color = T.stroke, Thickness = 1, Transparency = 0.45 }, f)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    }, f)
    mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
    return f
end

local function setBtnText(b, text)
    local l = b:FindFirstChild("Lbl")
    if l then l.Text = text else b.Text = text end
end

local function button(parent, text, style, size, onClick)
    local base = (style == "danger" and Color3.fromRGB(150, 50, 70)) or T.cardHi
    local b = mk("TextButton", {
        Size = size or UDim2.new(1, 0, 0, 36), BackgroundColor3 = base, Text = text, Font = FONT.bold,
        TextSize = 16, TextColor3 = T.text, AutoButtonColor = false, BorderSizePixel = 0,
        LayoutOrder = ord(parent),
    }, parent)
    corner(b, 8)
    local sc = mk("UIScale", {}, b)
    if style == "primary" then
        -- градиент красит и текст родителя, поэтому фон и подпись вынесены в дочерние объекты
        b.Text = ""
        b.BackgroundTransparency = 1
        local g = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, b)
        corner(g, 8)
        mk("UIGradient", { Color = ColorSequence.new(T.acc, T.acc2), Rotation = 20 }, g)
        mk("TextLabel", {
            Name = "Lbl", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text, Font = FONT.bold,
            TextSize = 16, TextColor3 = Color3.new(1, 1, 1), ZIndex = 2,
        }, b)
    end
    local hoverCol = base:Lerp(Color3.new(1, 1, 1), 0.14)
    b.MouseEnter:Connect(function() if style ~= "primary" then tw(b, 0.15, { BackgroundColor3 = hoverCol }) end end)
    b.MouseLeave:Connect(function()
        if style ~= "primary" then tw(b, 0.15, { BackgroundColor3 = base }) end
        tw(sc, 0.12, { Scale = 1 })
    end)
    b.InputBegan:Connect(function(i) if isPress(i) then tw(sc, 0.08, { Scale = 0.95 }) end end)
    b.InputEnded:Connect(function(i) if isPress(i) then tw(sc, 0.18, { Scale = 1 }, EASE.Back) end end)
    if onClick then b.Activated:Connect(onClick) end
    return b
end

local function row2(parent, ta, tb, styleA, styleB, fa, fb)
    local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = ord(parent) }, parent)
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    }, r)
    local a = button(r, ta, styleA, UDim2.new(0.5, -3, 1, 0), fa)
    local b = button(r, tb, styleB, UDim2.new(0.5, -3, 1, 0), fb)
    return a, b
end

-- переключатель с пояснением
local function toggleRow(parent, title, desc, get, set)
    local c = card(parent)
    local row = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false, LayoutOrder = 1,
    }, c)
    local txt = mk("Frame", {
        Size = UDim2.new(1, -60, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
    }, row)
    mk("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, txt)
    label(txt, title, 17, T.text, FONT.bold)
    if desc then label(txt, desc, 14, T.sub, FONT.reg) end
    local sw = mk("Frame", {
        Size = UDim2.fromOffset(46, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        BackgroundColor3 = T.off, BorderSizePixel = 0,
    }, row)
    corner(sw, 12)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, sw)
    corner(knob, 9)
    row.MouseEnter:Connect(function() tw(c, 0.15, { BackgroundColor3 = T.cardHi }) end)
    row.MouseLeave:Connect(function() tw(c, 0.15, { BackgroundColor3 = T.card }) end)
    row.Activated:Connect(function()
        set(not get())
        refresh()
    end)
    paint(function(instant)
        local on = get()
        local col = on and T.acc or T.off
        local pos = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        if instant then
            sw.BackgroundColor3, knob.Position = col, pos
        else
            tw(sw, 0.2, { BackgroundColor3 = col })
            tw(knob, 0.25, { Position = pos }, EASE.Back)
        end
    end)
    return c
end

-- ползунок: подписи по краям вместо цифр. o = { title, desc, left, right, get()->t, set(t), locked()->bool }
local function sliderRow(parent, o)
    local c = card(parent)
    local title = label(c, o.title, 17, T.text, FONT.bold)
    local desc = o.desc and label(c, o.desc, 14, T.sub, FONT.reg) or nil
    local area = mk("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = ord(c) }, c)
    local track = mk("Frame", {
        Size = UDim2.new(1, -16, 0, 8), Position = UDim2.new(0, 8, 0, 10), BackgroundColor3 = T.off, BorderSizePixel = 0,
    }, area)
    corner(track, 4)
    local fill = mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, track)
    corner(fill, 4)
    mk("UIGradient", { Color = ColorSequence.new(T.acc, T.acc2) }, fill)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3,
    }, track)
    corner(knob, 9)
    local kst = mk("UIStroke", { Color = T.acc, Thickness = 2 }, knob)
    local hit = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 4,
    }, area)
    local lL = mk("TextLabel", {
        Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0, 4, 0, 28), BackgroundTransparency = 1,
        Text = o.left or "", TextColor3 = T.sub, Font = FONT.med, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
    }, area)
    local lR = mk("TextLabel", {
        Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.5, -4, 0, 28), BackgroundTransparency = 1,
        Text = o.right or "", TextColor3 = T.sub, Font = FONT.med, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right,
    }, area)

    local dragging, dragInput = false, nil
    local function locked() return o.locked and o.locked() or false end
    local function visual(t, instant)
        if instant then
            fill.Size = UDim2.fromScale(t, 1)
            knob.Position = UDim2.fromScale(t, 0.5)
        else
            tw(fill, 0.2, { Size = UDim2.fromScale(t, 1) })
            tw(knob, 0.2, { Position = UDim2.fromScale(t, 0.5) })
        end
    end
    local function fromInput(i)
        local ax, aw = track.AbsolutePosition.X, track.AbsoluteSize.X
        local t = clamp((i.Position.X - ax) / math.max(aw, 1), 0, 1)
        o.set(t)
        visual(o.get(), true)
    end
    hit.InputBegan:Connect(function(i)
        if not isPress(i) or locked() then return end
        dragging, dragInput = true, i
        lockScroll(true)
        tw(knob, 0.12, { Size = UDim2.fromOffset(25, 25) }, EASE.Back)
        tw(kst, 0.12, { Thickness = 3 })
        fromInput(i)
    end)
    local function stop()
        dragging, dragInput = false, nil
        lockScroll(false)
        tw(knob, 0.18, { Size = UDim2.fromOffset(18, 18) }, EASE.Back)
        tw(kst, 0.18, { Thickness = 2 })
    end
    conns[#conns + 1] = UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i == dragInput then fromInput(i) end
    end)
    conns[#conns + 1] = UIS.InputEnded:Connect(function(i)
        if not dragging then return end
        if i == dragInput or (i.UserInputType == Enum.UserInputType.MouseButton1 and dragInput.UserInputType == Enum.UserInputType.MouseButton1) then
            stop()
        end
    end)

    paint(function(instant)
        if not dragging then visual(o.get(), instant) end
        local lk = locked()
        local a = lk and 0.55 or 0
        local m = lk and 0.65 or 0
        local objs = { { title, "TextTransparency", a }, { lL, "TextTransparency", a }, { lR, "TextTransparency", a },
            { track, "BackgroundTransparency", m }, { fill, "BackgroundTransparency", m }, { knob, "BackgroundTransparency", m } }
        if desc then objs[#objs + 1] = { desc, "TextTransparency", lk and 0.7 or 0 } end
        for _, e in ipairs(objs) do
            if instant then e[1][e[2]] = e[3] else tw(e[1], 0.2, { [e[2]] = e[3] }) end
        end
        kst.Transparency = lk and 0.7 or 0
    end)
    return c
end

-- линейное отображение CFG[key] <-> t
local function lin(key, lo, hi, step, cb)
    local function get() return clamp((CFG[key] - lo) / (hi - lo), 0, 1) end
    local function set(t)
        local v = lo + (hi - lo) * t
        if step then v = math.floor(v / step + 0.5) * step end
        CFG[key] = clamp(v, lo, hi)
        if cb then cb() end
    end
    return get, set
end

local function slider(parent, title, desc, left, right, key, lo, hi, step, cb, locked)
    local g, s = lin(key, lo, hi, step, cb)
    return sliderRow(parent, { title = title, desc = desc, left = left, right = right, get = g, set = s, locked = locked })
end

-- группа кнопок-чипов
local function chips(parent, items, getIdx, setIdx, cols, cellH)
    local c = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = ord(parent) }, parent)
    mk("UIGridLayout", {
        CellSize = UDim2.new(1 / cols, -((cols - 1) * 6) / cols, 0, cellH or 32), CellPadding = UDim2.fromOffset(6, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, c)
    local bs = {}
    for i, name in ipairs(items) do
        local b = mk("TextButton", {
            BackgroundColor3 = T.cardHi, Text = name, Font = FONT.bold, TextSize = 15, TextColor3 = T.text,
            AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i,
        }, c)
        corner(b, 8)
        b.Activated:Connect(function()
            setIdx(i)
            refresh()
        end)
        bs[i] = b
    end
    paint(function(instant)
        local cur = getIdx()
        for i, b in ipairs(bs) do
            local on = i == cur
            local col = on and T.acc or T.cardHi
            local tc = on and Color3.new(1, 1, 1) or T.sub
            if instant then
                b.BackgroundColor3, b.TextColor3 = col, tc
            else
                tw(b, 0.2, { BackgroundColor3 = col, TextColor3 = tc })
            end
        end
    end)
    return c
end

-- ===================== UI: ОКНО =================================
local WIN_W, WIN_H = 640, 410
local SIDE_W, HEAD_H = 150, 46

local holder = mk("Frame", {
    Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundTransparency = 1, Visible = false,
}, gui)
local fitScale = mk("UIScale", {}, holder)
local function fitWindow()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    fitScale.Scale = clamp(math.min((vp.X - 20) / WIN_W, (vp.Y - 20) / WIN_H, 1), 0.5, 1)
end
fitWindow()

local win = mk("CanvasGroup", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg, BorderSizePixel = 0, GroupTransparency = 1,
}, holder)
corner(win, 14)
mk("UIStroke", { Color = T.stroke, Thickness = 1.2, Transparency = 0.3 }, win)
local winScale = mk("UIScale", { Scale = 0.88 }, win)

-- шапка
local head = mk("Frame", { Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, win)
local accentLine = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
}, head)
local accentGrad = mk("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.acc), ColorSequenceKeypoint.new(0.5, T.acc2), ColorSequenceKeypoint.new(1, T.acc),
    }),
}, accentLine)
local orbLogo = mk("Frame", {
    Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(12, 10), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
}, head)
corner(orbLogo, 13)
local logoGrad = mk("UIGradient", { Color = ColorSequence.new(T.acc, T.acc2) }, orbLogo)
mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "A", Font = FONT.bold, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
}, orbLogo)
mk("TextLabel", {
    Size = UDim2.fromOffset(240, 22), Position = UDim2.fromOffset(46, 5), BackgroundTransparency = 1,
    Text = "Aero · Natural Disaster", Font = FONT.bold, TextSize = 19, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
}, head)
mk("TextLabel", {
    Size = UDim2.fromOffset(240, 14), Position = UDim2.fromOffset(46, 26), BackgroundTransparency = 1,
    Text = "версия 3.0 · русская", Font = FONT.med, TextSize = 13, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
}, head)
local pill = mk("TextLabel", {
    Size = UDim2.fromOffset(150, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -82, 0, 11),
    BackgroundColor3 = T.card, Text = "Под контролем: 0", Font = FONT.med, TextSize = 14, TextColor3 = T.sub, BorderSizePixel = 0,
}, head)
corner(pill, 12)

local function headBtn(txt, xoff, col)
    local b = mk("TextButton", {
        Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, xoff, 0, 8),
        BackgroundColor3 = T.card, Text = txt, Font = FONT.bold, TextSize = 20, TextColor3 = T.text,
        AutoButtonColor = false, BorderSizePixel = 0,
    }, head)
    corner(b, 8)
    b.MouseEnter:Connect(function() tw(b, 0.15, { BackgroundColor3 = col }) end)
    b.MouseLeave:Connect(function() tw(b, 0.15, { BackgroundColor3 = T.card }) end)
    return b
end
local minBtn = headBtn("–", -42, T.cardHi)
local closeBtn = headBtn("×", -8, T.bad)

-- перетаскивание окна за шапку
do
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    head.InputBegan:Connect(function(i)
        if isPress(i) then
            dragging, dragInput, dragStart, startPos = true, i, i.Position, holder.Position
        end
    end)
    conns[#conns + 1] = UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i == dragInput) then
            local d = i.Position - dragStart
            holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    conns[#conns + 1] = UIS.InputEnded:Connect(function(i)
        if dragging and (i == dragInput or i.UserInputType == Enum.UserInputType.MouseButton1) then dragging = false end
    end)
end

-- боковая панель
local side = mk("Frame", {
    Size = UDim2.new(0, SIDE_W, 1, -HEAD_H), Position = UDim2.fromOffset(0, HEAD_H), BackgroundColor3 = T.panel, BorderSizePixel = 0,
}, win)
mk("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, side)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, side)

-- область страниц
local content = mk("Frame", {
    Size = UDim2.new(1, -SIDE_W, 1, -HEAD_H), Position = UDim2.fromOffset(SIDE_W, HEAD_H), BackgroundTransparency = 1, ClipsDescendants = true,
}, win)
local cover = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20, Active = false,
}, content)

local TABS = { "Управление", "Рисунок", "Анимации", "Щит", "Игрок" }
local pages, tabBtns = {}, {}
for i = 1, #TABS do
    local p = mk("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.acc, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.Never, Visible = false,
    }, content)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14),
    }, p)
    mk("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, p)
    pages[i] = p
    scrollers[#scrollers + 1] = p
end

local selectTab
for i, name in ipairs(TABS) do
    local b = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i,
    }, side)
    local bg = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.acc, BackgroundTransparency = 1, BorderSizePixel = 0 }, b)
    corner(bg, 8)
    local bar = mk("Frame", {
        Size = UDim2.fromOffset(3, 0), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = T.acc2, BorderSizePixel = 0,
    }, b)
    corner(bar, 2)
    local txt = mk("TextLabel", {
        Size = UDim2.new(1, -18, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1, Text = name,
        Font = FONT.bold, TextSize = 17, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
    }, b)
    b.MouseEnter:Connect(function() if S.Tab ~= i then tw(bg, 0.15, { BackgroundTransparency = 0.92 }) end end)
    b.MouseLeave:Connect(function() if S.Tab ~= i then tw(bg, 0.15, { BackgroundTransparency = 1 }) end end)
    b.Activated:Connect(function() selectTab(i) end)
    tabBtns[i] = { bg = bg, bar = bar, txt = txt }
end
mk("TextLabel", {
    Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "RightShift — показать / скрыть меню",
    Font = FONT.reg, TextSize = 13, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = 99, TextYAlignment = Enum.TextYAlignment.Top,
}, side)

selectTab = function(i, instant)
    S.Tab = i
    for k, pg in ipairs(pages) do pg.Visible = (k == i) end
    for k, tb in ipairs(tabBtns) do
        local on = k == i
        if instant then
            tb.bg.BackgroundTransparency = on and 0.82 or 1
            tb.bar.Size = UDim2.fromOffset(3, on and 22 or 0)
            tb.txt.TextColor3 = on and T.text or T.sub
        else
            tw(tb.bg, 0.2, { BackgroundTransparency = on and 0.82 or 1 })
            tw(tb.bar, 0.3, { Size = UDim2.fromOffset(3, on and 22 or 0) }, EASE.Back)
            tw(tb.txt, 0.2, { TextColor3 = on and T.text or T.sub })
        end
    end
    if not instant then
        cover.BackgroundTransparency = 0.55
        tw(cover, 0.3, { BackgroundTransparency = 1 })
        pages[i].Position = UDim2.fromOffset(0, 14)
        tw(pages[i], 0.35, { Position = UDim2.new() }, EASE.Quart)
    end
    scan.last = 0
    refresh()
end

-- ===================== СТРАНИЦА 1: УПРАВЛЕНИЕ ===================
do
    local p = pages[1]
    toggleRow(p, "Управление предметами",
        "Берёт под контроль свободные (не прибитые к земле) предметы на карте и двигает их. Рисунки, анимации и щит работают только когда это включено.",
        function() return S.Parts end, setParts)

    section(p, "Режим движения")
    local mc = card(p)
    local modeNames = {}
    for i, m in ipairs(MODES) do modeNames[i] = m.name end
    chips(mc, modeNames, function() return S.Mode end, function(i)
        if MODES[i].id == "Figure" and not fig then
            toast("Сначала нарисуй фигуру или запусти анимацию", "warn")
            return
        end
        S.Mode = i
        resetHeld()
    end, 3, 34)
    local modeDesc = label(mc, "", 14, T.sub, FONT.reg)
    paint(function() modeDesc.Text = MODES[S.Mode].desc end)

    section(p, "Поиск и количество")
    local rg = function()
        if CFG.ScanRadius == math.huge then return 1 end
        return clamp((CFG.ScanRadius - 50) / 1450, 0, 0.97)
    end
    local rs = function(t)
        CFG.ScanRadius = (t >= 0.98) and math.huge or (50 + t * 1450)
        scan.last = 0
    end
    sliderRow(p, { title = "Радиус поиска", desc = "Как далеко от тебя искать свободные предметы.", left = "Ближе", right = "Вся карта", get = rg, set = rs })
    slider(p, "Радиус орбиты", "Как далеко от тебя летают предметы в режимах «Орбита» и «Вихрь».", "Ближе", "Дальше", "OrbitRadius", 10, 80, 1)
    slider(p, "Максимум предметов", "Сколько предметов одновременно держать под контролем.", "Меньше", "Больше", "MaxParts", 100, 2000, 50, function() scan.last = 0 end)

    section(p, "Возможности твоего эксплойта")
    local cc = card(p)
    label(cc, "Расширение радиуса симуляции: " .. (HAS_SIM and "есть" or "НЕТ — далёкие предметы могут не слушаться"), 14, HAS_SIM and T.ok or T.warn, FONT.med)
    label(cc, "Проверка владельца предмета: " .. (HAS_OWNER and "есть" or "НЕТ — управляются все найденные"), 14, HAS_OWNER and T.ok or T.warn, FONT.med)
end

-- ===================== СТРАНИЦА 2: РИСУНОК ======================
local statsLabel, liveDraw
do
    local p = pages[2]
    section(p, "Холст")
    local dc = card(p)
    local drow = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, dc)
    mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, drow)

    local canvas = mk("Frame", {
        Size = UDim2.fromOffset(CANVAS, CANVAS), BackgroundColor3 = Color3.fromRGB(10, 11, 17), BorderSizePixel = 0,
        ClipsDescendants = true, LayoutOrder = 1,
    }, drow)
    corner(canvas, 8)
    mk("UIStroke", { Color = T.stroke, Thickness = 1 }, canvas)
    local trailLayer = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, canvas)
    local previewLayer = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, canvas)
    local hint = mk("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Text = "Рисуй здесь пальцем или мышью",
        TextColor3 = Color3.fromRGB(100, 106, 135), Font = FONT.med, TextSize = 16,
    }, canvas)
    local hit = mk("TextButton", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5,
    }, canvas)

    local col = mk("Frame", { Size = UDim2.new(0, 196, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, drow)
    mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, col)

    button(col, "Сформировать (V)", "primary", UDim2.new(1, 0, 0, 38), function() formFigure() end)
    button(col, "Отпустить фигуру", "ghost", UDim2.new(1, 0, 0, 32), function()
        releaseFigure()
        toast("Фигура отпущена", "warn")
    end)
    local undoB, clrB = row2(col, "Отменить", "Очистить", "ghost", "danger")
    label(col, "Толщина кисти", 13, T.sub, FONT.med)
    chips(col, { BRUSH[1].name, BRUSH[2].name, BRUSH[3].name }, function() return S.Brush end, function(i) S.Brush = i end, 3, 28)
    label(col, "Заливка", 13, T.sub, FONT.med)
    chips(col, { "Контур", "Силуэт" }, function() return S.Fill and 2 or 1 end, function(i)
        S.Fill = (i == 2)
        replan()
    end, 2, 28)

    local scanB = button(dc, "Поиск предметов заново", "ghost", UDim2.new(1, 0, 0, 30), function()
        scanSync(true)
        replan()
        toast(string.format("Найдено свободных предметов: %d", candTotal), "ok")
    end)

    section(p, "Состояние")
    local sc = card(p)
    statsLabel = label(sc, "", 14, T.text, FONT.reg, { RichText = true })
    liveDraw = label(sc, "", 14, T.acc2, FONT.med)

    setStats = function(text) statsLabel.Text = text end

    section(p, "Размер и положение")
    toggleRow(p, "Авто-размер",
        "Сам подбирает размер и, если нужно, отодвигает фигуру, чтобы она целиком поместилась в кадр.",
        function() return CFG.FigAuto end, function(v) CFG.FigAuto = v; markDirty("fig") end)
    slider(p, "Размер рисунка", "Работает, когда «Авто-размер» выключен.", "Меньше", "Больше", "FigSize", 20, 200, 5,
        function() markDirty("fig") end, function() return CFG.FigAuto end)
    slider(p, "Расстояние от меня", "Насколько далеко перед тобой появится рисунок.", "Ближе", "Дальше", "FigDist", 15, 160, 1,
        function() markDirty("fig") end)
    slider(p, "Высота", "Поднимает или опускает рисунок.", "Ниже", "Выше", "FigHeight", -15, 40, 1, function() markDirty("fig") end)
    slider(p, "Толщина рисунка", "Сколько слоёв предметов, если их хватает.", "Тоньше", "Толще", "FigLayers", 1, 4, 1, function() markDirty("fig") end)
    toggleRow(p, "Следовать за камерой",
        "Рисунок остаётся перед тобой, куда бы ты ни повернулся. Выключи — он зафиксируется в мире.",
        function() return CFG.FigFollow end, function(v)
            CFG.FigFollow = v
            if fig and not v then fig.repin = true end
        end)

    -- ввод штрихов
    local function canvasPos(i)
        local ap, as = canvas.AbsolutePosition, canvas.AbsoluteSize
        local x = clamp((i.Position.X - ap.X) / math.max(as.X, 1), 0, 1) * CANVAS
        local y = clamp((i.Position.Y - ap.Y) / math.max(as.Y, 1), 0, 1) * CANVAS
        return x, y
    end

    local function newDot(parent)
        local f = mk("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5) }, parent)
        local c = mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
        return f, c
    end

    local function addPoint(stroke, x, y)
        stroke.pts[#stroke.pts + 1] = { x = x, y = y }
        local sz = math.max(3, stroke.r * 2)
        local f = newDot(trailLayer)
        f.Size = UDim2.fromOffset(sz, sz)
        f.Position = UDim2.fromOffset(x, y)
        f.BackgroundColor3 = TRAIL
        f.BackgroundTransparency = 0.5
        stroke.dots[#stroke.dots + 1] = f
    end

    local function renderPreview(pl)
        local P = pl and pl.P or 0
        for i = 1, P do
            local s = pl.slots[i]
            local info = pl.fit[s.part]
            local d = dots[i]
            if not d then
                local f, c = newDot(previewLayer)
                d = { f = f, c = c }
                dots[i] = d
            end
            local sz = clamp(info.ext / pl.scale, 3, 30)
            d.f.Visible = true
            d.f.Size = UDim2.fromOffset(sz, sz)
            d.f.Position = UDim2.fromOffset(s.px, s.py)
            d.f.BackgroundColor3 = info.color
            if info.shape == "Ball" then
                d.c.CornerRadius = UDim.new(0.5, 0)
                d.f.Rotation = 0
            else
                local r = (info.group == "Камень" or info.shape == "Mesh") and 0.32 or 0.08
                d.c.CornerRadius = UDim.new(r, 0)
                d.f.Rotation = (s.part * 37) % 90
            end
        end
        for i = P + 1, #dots do dots[i].f.Visible = false end
    end

    replan = function()
        hint.Visible = #strokes == 0
        if #strokes == 0 then
            plan = nil
            renderPreview(nil)
            setStats(string.format("Свободных предметов: %d (лимит %d)\nНарисуй фигуру и нажми «Сформировать».", candTotal, CFG.MaxParts))
            return
        end
        local pl, err = buildPlan()
        plan = pl
        renderPreview(pl)
        lastPlanN = #candidates
        if pl then
            setStats(planText(pl))
        else
            setStats("Нельзя построить: " .. tostring(err))
        end
    end

    onScanDone = function()
        if drawing then return end
        if #strokes == 0 then
            setStats(string.format("Свободных предметов: %d (лимит %d)\nНарисуй фигуру и нажми «Сформировать».", candTotal, CFG.MaxParts))
            return
        end
        local n = #candidates
        if math.abs(n - lastPlanN) > math.max(3, lastPlanN * 0.05) then replan() end
    end

    hit.InputBegan:Connect(function(i)
        if not isPress(i) or drawing then return end
        drawing, drawInput = true, i
        lockScroll(true)
        local x, y = canvasPos(i)
        curStroke = { r = BRUSH[S.Brush].r, pts = {}, dots = {} }
        strokes[#strokes + 1] = curStroke
        addPoint(curStroke, x, y)
        hint.Visible = false
    end)
    conns[#conns + 1] = UIS.InputChanged:Connect(function(i)
        if not drawing or not curStroke then return end
        local isMouse = i.UserInputType == Enum.UserInputType.MouseMovement
        local isTouch = i.UserInputType == Enum.UserInputType.Touch and i == drawInput
        if not (isMouse or isTouch) then return end
        local x, y = canvasPos(i)
        local last = curStroke.pts[#curStroke.pts]
        local dx, dy = x - last.x, y - last.y
        if dx * dx + dy * dy >= MINSEG * MINSEG then addPoint(curStroke, x, y) end
    end)
    conns[#conns + 1] = UIS.InputEnded:Connect(function(i)
        if not drawing then return end
        local mouseUp = drawInput and drawInput.UserInputType == Enum.UserInputType.MouseButton1
            and i.UserInputType == Enum.UserInputType.MouseButton1
        if i == drawInput or mouseUp then
            drawing, drawInput, curStroke = false, nil, nil
            lockScroll(false)
            replan()
            if fig and fig.kind == "draw" then markDirty("fig") end
        end
    end)

    local function clearStrokes(onlyLast)
        local from = onlyLast and #strokes or 1
        for k = #strokes, from, -1 do
            for _, f in ipairs(strokes[k].dots) do pcall(function() f:Destroy() end) end
            strokes[k] = nil
        end
        replan()
    end
    undoB.Activated:Connect(function() clearStrokes(true) end)
    clrB.Activated:Connect(function() clearStrokes(false) end)
    replan()
end

-- ===================== СТРАНИЦА 3: АНИМАЦИИ =====================
local liveAnim
do
    local p = pages[3]
    local note = card(p)
    label(note, "Тестовый раздел", 17, T.warn, FONT.bold)
    label(note, "Анимации собираются из тех же свободных предметов и двигаются перед тобой. Размер, расстояние и щит берутся из вкладок «Рисунок» и «Щит».", 14, T.sub, FONT.reg)

    for _, a in ipairs(ANIMS) do
        local c = card(p)
        label(c, a.name, 18, T.text, FONT.bold)
        label(c, a.desc, 14, T.sub, FONT.reg)
        local b = button(c, "Запустить", "primary", UDim2.new(1, 0, 0, 36), function()
            if S.Anim == a.id then
                releaseFigure()
                toast("Анимация остановлена", "warn")
            else
                startAnim(a.id)
            end
        end)
        paint(function()
            setBtnText(b, (S.Anim == a.id) and "Остановить" or "Запустить")
        end)
    end

    section(p, "Настройки анимации")
    slider(p, "Скорость", "Как быстро двигаются частицы.", "Медленно", "Быстро", "AnimSpeed", 0.3, 3, 0.05)
    slider(p, "Количество частиц", "Сколько предметов участвует (применится сразу).", "Меньше", "Больше", "AnimCount", 60, 600, 10,
        function() markDirty("anim") end)
    slider(p, "Расстояние от меня", "Насколько далеко перед тобой играет анимация.", "Ближе", "Дальше", "FigDist", 15, 160, 1,
        function() markDirty("fig") end)
    toggleRow(p, "Авто-размер",
        "Подбирает размер анимации под экран. Выключи — размер возьмётся из ползунка во вкладке «Рисунок».",
        function() return CFG.FigAuto end, function(v) CFG.FigAuto = v; markDirty("fig") end)
    section(p, "Состояние")
    local sc = card(p)
    liveAnim = label(sc, "", 14, T.acc2, FONT.med)
end

-- ===================== СТРАНИЦА 4: ЩИТ ==========================
local shieldInfo
do
    local p = pages[4]
    toggleRow(p, "Щит от предметов",
        "Не даёт предметам под твоим контролем подлететь к тебе: например, лаве, которой ты рисуешь. Цели рисунков никогда не лежат внутри щита, поэтому фигура остаётся целой.",
        function() return CFG.Shield end, function(v) CFG.Shield = v; markDirty("fig") end)
    slider(p, "Размер щита", "Чем больше щит, тем дальше от тебя держатся предметы.", "Меньше", "Больше", "ShieldRadius", 6, 32, 1,
        function() markDirty("fig") end, function() return not CFG.Shield end)
    toggleRow(p, "Показывать щит",
        "Полупрозрачный купол вокруг персонажа (виден только тебе).",
        function() return CFG.ShieldShow end, function(v) CFG.ShieldShow = v end)
    section(p, "Состояние")
    local sc = card(p)
    shieldInfo = label(sc, "", 14, T.acc2, FONT.med)
    local lim = card(p)
    label(lim, "Важно", 16, T.warn, FONT.bold)
    label(lim, "Щит защищает только от предметов, которыми управляешь ты. Предметы без твоего контроля (чужие или вне радиуса симуляции) он остановить не может.", 14, T.sub, FONT.reg)
end

-- ===================== СТРАНИЦА 5: ИГРОК ========================
do
    local p = pages[5]
    toggleRow(p, "Полёт", "Летай по карте. Двигайся как обычно, камера задаёт направление.", function() return S.Fly end, setFly)
    slider(p, "Скорость полёта", nil, "Медленно", "Быстро", "FlySpeed", 20, 200, 5)
    ui.vert = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = ord(p) }, p)
    mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, ui.vert)
    local upB = button(ui.vert, "Вверх (E)", "ghost", UDim2.new(0.5, -3, 1, 0))
    local downB = button(ui.vert, "Вниз (Q)", "ghost", UDim2.new(0.5, -3, 1, 0))
    local function holdBtn(b, key)
        b.InputBegan:Connect(function(i) if isPress(i) then S[key] = true end end)
        b.InputEnded:Connect(function(i) if isPress(i) then S[key] = false end end)
    end
    holdBtn(upB, "up")
    holdBtn(downB, "down")
    paint(function() ui.vert.Visible = S.Fly end)
    toggleRow(p, "ESP (подсветка игроков)", "Показывает игроков сквозь стены: имя, расстояние и здоровье.", function() return S.Esp end, setEsp)
end

-- ===================== ОКРУГЛАЯ КНОПКА И ПОКАЗ ==================
local orb = mk("TextButton", {
    Name = "Orb", Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
    BackgroundTransparency = 1, Text = "", AutoButtonColor = false, BorderSizePixel = 0, Visible = false,
}, gui)
local orbBg = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, orb)
corner(orbBg, 23)
local orbGrad = mk("UIGradient", { Color = ColorSequence.new(T.acc, T.acc2) }, orbBg)
mk("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.6 }, orbBg)
mk("TextLabel", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "A", Font = FONT.bold, TextSize = 24,
    TextColor3 = Color3.new(1, 1, 1), ZIndex = 2,
}, orb)
local orbScale = mk("UIScale", { Scale = 0 }, orb)

local function showMenu(v)
    menuOpen = v
    if v then
        fitWindow()
        holder.Visible = true
        tw(win, 0.35, { GroupTransparency = 0 }, EASE.Quart)
        tw(winScale, 0.5, { Scale = 1 }, EASE.Back)
        tw(orbScale, 0.2, { Scale = 0 })
        task.delay(0.2, function() if menuOpen then orb.Visible = false end end)
        scan.last = 0
    else
        tw(win, 0.22, { GroupTransparency = 1 })
        tw(winScale, 0.22, { Scale = 0.9 })
        orb.Visible = true
        tw(orbScale, 0.45, { Scale = 1 }, EASE.Back)
        task.delay(0.25, function() if not menuOpen then holder.Visible = false end end)
    end
end
orb.Activated:Connect(function() showMenu(true) end)
minBtn.Activated:Connect(function() showMenu(false) end)
closeBtn.Activated:Connect(function() Destroy() end)

-- ===================== ВВОД / ЦИКЛ ==============================
track(UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    local k = i.KeyCode
    if k == CFG.Keys.Menu then showMenu(not menuOpen)
    elseif k == CFG.Keys.Fly then setFly(not S.Fly)
    elseif k == CFG.Keys.Parts then setParts(not S.Parts)
    elseif k == CFG.Keys.Esp then setEsp(not S.Esp)
    elseif k == CFG.Keys.Mode then nextMode()
    elseif k == CFG.Keys.Draw then
        if not menuOpen then showMenu(true) end
        selectTab(2)
    elseif k == CFG.Keys.Form then formFigure()
    elseif k == CFG.Keys.Up then S.up = true
    elseif k == CFG.Keys.Down then S.down = true
    end
end))
track(UIS.InputEnded:Connect(function(i)
    local k = i.KeyCode
    if k == CFG.Keys.Up then S.up = false
    elseif k == CFG.Keys.Down then S.down = false
    end
end))
track(Players.PlayerRemoving:Connect(espRemove))

local function liveText()
    local f = fig
    if not f then return "Формация не создана." end
    local cam = Workspace.CurrentCamera
    local inView = false
    if cam and f.cf then
        local _, on = cam:WorldToViewportPoint(f.cf.Position)
        inView = on
    end
    local arrived, got = 0, 0
    for k = 1, f.n do
        local root = f.slotRoot[k]
        if root and root.Parent then
            got = got + 1
            local lp = f.fn and f.fn(k, f.phase) or f.loc[k]
            if f.cf and (root.Position - f.cf:PointToWorldSpace(lp)).Magnitude < 4 then arrived = arrived + 1 end
        end
    end
    return string.format("В кадре: %s | дистанция %d студов | на месте %d из %d (захвачено %d)",
        inView and "да" or "нет", math.floor(f.distEff + 0.5), arrived, f.n, got)
end

local function shieldText()
    local _, hrp = getChar()
    if not hrp then return "Нет персонажа." end
    local nearest = math.huge
    for i = 1, #candidates do
        local rec = candidates[i]
        if rec.own and rec.root.Parent then
            local d = (rec.root.Position - hrp.Position).Magnitude - radOf(rec)
            if d < nearest then nearest = d end
        end
    end
    local state
    if not S.Parts then
        state = "ждёт включения управления предметами"
    elseif CFG.Shield then
        state = "активен"
    else
        state = "выключен"
    end
    local near = nearest == math.huge and "—" or string.format("%d студов", math.floor(nearest + 0.5))
    return string.format("Щит: %s\nБлижайший предмет до края: %s (щит %d)\nОтклонений за секунду: %d",
        state, near, math.floor(CFG.ShieldRadius), shieldHitsShown)
end

local function updateStatus()
    local own = 0
    for i = 1, #candidates do
        if candidates[i].own then own = own + 1 end
    end
    pill.Text = "Под контролем: " .. own
    pill.TextColor3 = (S.Parts and own > 0) and T.ok or T.sub
    if menuOpen then
        if S.Tab == 2 and liveDraw then liveDraw.Text = liveText() end
        if S.Tab == 3 and liveAnim then liveAnim.Text = liveText() end
        if S.Tab == 4 and shieldInfo then shieldInfo.Text = shieldText() end
    end
end

local errOnce = {}
local function guard(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not errOnce[name] then
        errOnce[name] = true
        warn("[Aero] " .. name .. ": " .. tostring(err))
    end
end

local espAcc, statAcc, hitAcc = 0, 0, 0
track(RunService.Heartbeat:Connect(function(dt)
    guard("scan", scanTick)
    if S.Parts then guard("parts", stepParts, os.clock(), dt) end
    if S.Fly then guard("fly", stepFly) end
    guard("shield", stepShield, os.clock(), dt)
    if S.Esp then
        espAcc = espAcc + dt
        if espAcc >= CFG.EspInterval then
            espAcc = 0
            guard("esp", espUpdate)
        end
    end
    if dirty and os.clock() - dirtyAt > 0.15 then
        local k = dirty
        dirty = nil
        guard("refit", applyDirty, k)
    end
    statAcc = statAcc + dt
    if statAcc >= 0.25 then
        statAcc = 0
        guard("status", updateStatus)
    end
    hitAcc = hitAcc + dt
    if hitAcc >= 1 then
        shieldHitsShown = math.floor(shieldHits / hitAcc + 0.5)
        shieldHits, hitAcc = 0, 0
    end
    -- анимация шапки
    local t = os.clock()
    accentGrad.Offset = Vector2.new(math.sin(t * 0.8) * 0.5, 0)
    logoGrad.Rotation = (t * 90) % 360
    orbGrad.Rotation = (t * 60) % 360
end))

-- ===================== ОЧИСТКА ==================================
Destroy = function()
    S.Parts, S.Fly, S.Esp = false, false, false
    S.up, S.down = false, false
    menuOpen = false
    fig = nil
    pcall(releaseAll)
    pcall(flyOff)
    pcall(espClear)
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    conns = {}
    pcall(function() espFolder:Destroy() end)
    pcall(function() if shieldPart then shieldPart:Destroy() end end)
    pcall(function() gui:Destroy() end)
    if genv.__AeroNDS and genv.__AeroNDS.Destroy == Destroy then
        genv.__AeroNDS = nil
    end
end
genv.__AeroNDS = { Destroy = Destroy }

-- ===================== СТАРТ ====================================
selectTab(1, true)
refresh()
showMenu(true)
toast("Aero v3 загружен. Меню: RightShift или круглая кнопка", "ok")
print("[Aero] v3.0 загружен. Управление / Полёт / ESP выключены. RightShift — меню.")
