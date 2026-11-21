-- VOICE TIMING SIMULATOR (the owner: "can you test the speed of how words are spoken on your side with latency
-- and other things? I can't just use assumptions"). Runs the add-on's REAL VOICE.loop / VOICE.play on a model of
-- the game, in simulated seconds:
--   * CraftOS events: os.startTimer / os.pullEvent(Raw) / os.queueEvent / sleep, and parallel.waitForAll /
--     waitForAny written like CraftOS's own (each coroutine gets the events, with its filter)
--   * the speech service: http.get takes `latency` s (other coroutines run meanwhile, as in the game)
--   * the sound work: decoding costs `work` s per second of speech and BLOCKS the computer (as Lua does)
--   * a Speaker like CC:Tweaked's: one buffer playing + one waiting; playAudio refuses when one is waiting;
--     "speaker_audio_empty" when the waiting one starts; stop() drops both
-- VOICE_SIM.run(opt) -> { [text] = first-sound time }, the event log.
-- opt: latency, work (s per s of speech), cps (characters a second), own (a line it says by itself at t = 0),
--      askAt, answer, cache (true: what was said once is cached - the add-on's own floppy cache does that)
VOICE_SIM = {}
function VOICE_SIM.run(opt)
  local saved = { os = os, sleep = sleep, parallel = parallel, http = http, CLOCK = CLOCK,
                  pre = package.preload["cc.audio.dfpwm"], loaded = package.loaded["cc.audio.dfpwm"],
                  tick = VOICE.tick, speakers = VOICE.speakers, running = state.running }
  local T0 = CLOCK
  local now = 0
  local function setNow(t) now = t CLOCK = T0 + t end
  local events, timers, nextTimer = {}, {}, 0
  local log, first = {}, {}
  local ids, names = {}, {}            -- text <-> a sample value (the speaker sees which line it plays)
  local function idOf(text)
    if not ids[text] then names[#names + 1] = text ids[text] = #names end
    return ids[text]
  end
  local function nameOfId(v) return names[v] end
  local fakeOs = {}
  for k, v in pairs(saved.os) do fakeOs[k] = v end
  fakeOs.clock = function() return T0 + now end
  fakeOs.startTimer = function(d)
    nextTimer = nextTimer + 1
    timers[nextTimer] = now + math.max(0, tonumber(d) or 0)
    return nextTimer
  end
  fakeOs.cancelTimer = function(id) timers[id] = nil end
  fakeOs.queueEvent = function(...) events[#events + 1] = table.pack(...) end
  fakeOs.pullEventRaw = function(filter) return coroutine.yield(filter) end
  fakeOs.pullEvent = function(filter)
    local e = table.pack(coroutine.yield(filter))
    if e[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(e, 1, e.n)
  end
  local function fakeSleep(d)
    local id = fakeOs.startTimer(d)
    repeat local _, a = fakeOs.pullEvent("timer") until a == id
  end
  -- CraftOS parallel (rom/apis/parallel.lua, same logic)
  local function runUntilLimit(routines, limit)
    local count, living, filters, ev = #routines, #routines, {}, { n = 0 }
    while true do
      for n = 1, count do
        local r = routines[n]
        if r and (filters[r] == nil or filters[r] == ev[1] or ev[1] == "terminate") then
          local ok, param = coroutine.resume(r, table.unpack(ev, 1, ev.n))
          if not ok then error(param, 0) end
          filters[r] = param
          if coroutine.status(r) == "dead" then
            routines[n] = nil
            living = living - 1
            if living <= limit then return n end
          end
        end
      end
      ev = table.pack(fakeOs.pullEventRaw())
    end
  end
  local fakeParallel = {
    waitForAny = function(...)
      local rs = {}
      for i, f in ipairs({ ... }) do rs[i] = coroutine.create(f) end
      return runUntilLimit(rs, #rs - 1)
    end,
    waitForAll = function(...)
      local rs = {}
      for i, f in ipairs({ ... }) do rs[i] = coroutine.create(f) end
      return runUntilLimit(rs, 0)
    end,
  }
  -- the speech service: `latency` s, then DFPWM bytes for the text (6000 bytes = 1 s at 48 kHz)
  local cache = {}
  local fakeHttp = { get = function(url)
    local text = (url:match("text=([^&]*)") or ""):gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    local id = fakeOs.startTimer(opt.latency or 1)
    repeat local ev, a = fakeOs.pullEventRaw() until ev == "timer" and a == id
    log[#log + 1] = string.format("%6.2f  fetched '%s'", now, text)
    local secs = math.max(0.3, #text / (opt.cps or 14))
    local v = idOf(text)
    local data = string.char(v) .. string.rep("\0", math.floor(secs * 6000) - 1)
    return { readAll = function() return data end, close = function() end }
  end }
  -- the decoder: 8 samples a byte, every sample = the line's number; costs `work` s per s of speech (blocking)
  package.loaded["cc.audio.dfpwm"] = nil
  package.preload["cc.audio.dfpwm"] = function()
    return { make_decoder = function()
      local v
      return function(s)
        v = v or s:byte(1)
        local out = {}
        for i = 1, #s * 8 do out[i] = v end
        setNow(now + (opt.work or 0.04) * (#s * 8 / 48000))
        return out
      end
    end }
  end
  -- the Speaker
  local spk = { playing = nil, playEnd = 0, waiting = nil, plays = 0, stops = 0 }
  local function startBuf(buf, at)
    spk.playing = buf
    spk.playEnd = at + #buf / 48000
    local name = nameOfId(buf[1])
    if name and not first[name] then
      first[name] = at
      log[#log + 1] = string.format("%6.2f  FIRST SOUND of '%s'", at, name)
    end
  end
  local speakerObj = {
    playAudio = function(buf)
      if spk.waiting then return false end
      spk.plays = spk.plays + 1
      if not spk.playing then startBuf(buf, now) else spk.waiting = buf end
      return true
    end,
    playSound = function() return true end,
    stop = function() spk.stops = spk.stops + 1 spk.playing, spk.waiting = nil, nil
      log[#log + 1] = string.format("%6.2f  speaker STOPPED", now) end,
  }
  VOICE.speakers = function() return { speakerObj } end
  VOICE.tick = function() end
  os, sleep, parallel, http = fakeOs, fakeSleep, fakeParallel, fakeHttp
  state.running = true
  -- the chat: a question at askAt -> the answer queued (as the chat worker does)
  local done = false
  local askedAt
  local main = coroutine.create(function()
    fakeParallel.waitForAny(
      function() VOICE.loop() end,
      function()
        if opt.own then VOICE.say(opt.own) fakeOs.queueEvent("voice_say") end
        fakeSleep(opt.askAt or 3)
        log[#log + 1] = string.format("%6.2f  ASKED", now)
        askedAt = now
        VOICE.heardAt = os.clock()
        VOICE.say(opt.answer, nil, true)
        fakeOs.queueEvent("voice_say")
        fakeSleep(opt.runFor or 40)
      end)
    done = true
  end)
  local filter
  local okR, errR = coroutine.resume(main)
  if not okR then error(errR, 0) end
  filter = errR
  local guard = 0
  while not done and coroutine.status(main) ~= "dead" and guard < 200000 do
    guard = guard + 1
    -- the speaker moves on by itself
    if spk.playing and spk.playEnd <= now then
      spk.playing = nil
      if spk.waiting then
        local w = spk.waiting
        spk.waiting = nil
        startBuf(w, spk.playEnd)
        fakeOs.queueEvent("speaker_audio_empty", "speaker_0")
      end
    end
    local ev = table.remove(events, 1)
    if not ev then
      -- nothing to do: on to the next timer / the speaker's next change
      local tNext, idNext = math.huge, nil
      for id, t in pairs(timers) do if t < tNext or (t == tNext and id < idNext) then tNext, idNext = t, id end end
      local tSpk = spk.playing and spk.playEnd or math.huge
      if tSpk < tNext then setNow(math.max(now, tSpk))
      elseif idNext then
        timers[idNext] = nil
        setNow(math.max(now, tNext))
        ev = table.pack("timer", idNext)
      else break end
    end
    if ev and (filter == nil or filter == ev[1] or ev[1] == "terminate") then
      local ok, f = coroutine.resume(main, table.unpack(ev, 1, ev.n))
      if not ok then error(f, 0) end
      filter = f
    end
  end
  os, sleep, parallel, http, CLOCK = saved.os, saved.sleep, saved.parallel, saved.http, saved.CLOCK + now
  package.preload["cc.audio.dfpwm"], package.loaded["cc.audio.dfpwm"] = saved.pre, saved.loaded
  VOICE.tick, VOICE.speakers, state.running = saved.tick, saved.speakers, saved.running
  VOICE.queue, VOICE.pre, VOICE.busyUntil, VOICE.cutNow = {}, nil, nil, nil
  return { first = first, log = log, stops = spk.stops, askedAt = askedAt }
end
