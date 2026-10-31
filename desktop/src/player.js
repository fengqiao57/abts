import { useEffect, useRef, useState } from 'react';

export function usePlayer(state, notify) {
  const audio = useRef(null);
  if (!audio.current) audio.current = new Audio();
  const current = useRef(null);
  const stateRef = useRef(state);
  stateRef.current = state;
  const [track, setTrack] = useState(null);
  const [playing, setPlaying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [offline, setOffline] = useState(false);
  const [deadline, setDeadline] = useState(null);
  const [remaining, setRemaining] = useState(0);
  const requestId = useRef(0);
  const lastSave = useRef(0);
  const retryCount = useRef(0);
  const openRef = useRef();
  const nextRef = useRef();
  const toggleRef = useRef();
  const save = () => {
    const c = current.current, a = audio.current;
    if (c) window.abts.progress(c.book.bvid, c.chapter.cid, a.currentTime || 0,
      Number.isFinite(a.duration) ? a.duration : c.chapter.duration || 0).catch(() => {});
  };
  async function open(book, chapter, resumeAt, reconnect = false) {
    if (!book?.chapters?.length) return;
    if (!reconnect) { save(); retryCount.current = 0; }
    const id = ++requestId.current;
    const a = audio.current;
    a.pause();
    a.removeAttribute('src');
    a.load();
    current.current = null;
    setLoading(true); setPosition(0); setDuration(chapter.duration); setTrack({ book, chapter });
    const progress = stateRef.current?.history?.[book.bvid]?.chapters?.[chapter.cid];
    let offset = resumeAt ?? progress?.position ?? 0;
    if (offset >= (progress?.duration || chapter.duration) - 2) offset = 0;
    try {
      const result = await window.abts.resolve(book.bvid, chapter.cid);
      if (id !== requestId.current) return;
      current.current = { book, chapter };
      setOffline(result.offline);
      a.onloadedmetadata = () => {
        if (id !== requestId.current) return;
        a.currentTime = Math.min(offset, Math.max(0, (Number.isFinite(a.duration) ? a.duration : chapter.duration) - 0.2));
        a.playbackRate = stateRef.current?.settings.rate || 1;
        a.volume = stateRef.current?.settings.volume ?? 0.8;
      };
      a.src = result.url;
      await a.play();
      if ('mediaSession' in navigator) {
        navigator.mediaSession.metadata = new MediaMetadata({
          title: chapter.title, artist: book.author, album: book.title,
          artwork: book.pic ? [{ src: book.pic }] : []
        });
      }
    } catch (error) {
      if (id === requestId.current) {
        setLoading(false); setPlaying(false);
        notify(error.message);
      }
    }
  }
  openRef.current = open;
  async function next(delta = 1, automatic = false) {
    const c = current.current;
    if (!c) return;
    const index = c.book.chapters.findIndex(ch => ch.cid === c.chapter.cid);
    const chapter = c.book.chapters[index + delta];
    if (chapter) await open(c.book, chapter, automatic ? 0 : undefined);
    else if (!automatic) notify(delta > 0 ? '已经是最后一集' : '已经是第一集');
  }
  nextRef.current = next;
  useEffect(() => {
    const a = audio.current;
    const onPlay = () => {
      setPlaying(true); setLoading(false);
      window.abts.playing(true).catch(() => {});
      if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
    };
    const onPause = () => {
      setPlaying(false); save();
      window.abts.playing(false).catch(() => {});
      if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
    };
    const onTime = () => {
      setPosition(a.currentTime);
      if (Date.now() - lastSave.current > 5000) { lastSave.current = Date.now(); save(); }
    };
    const onDuration = () => { if (Number.isFinite(a.duration)) setDuration(a.duration); };
    const onEnded = () => {
      save(); setPlaying(false); window.abts.playing(false).catch(() => {});
      if (!stateRef.current?.settings.stopAfter) void nextRef.current(1, true);
    };
    const onError = () => {
      setLoading(false);
      const c = current.current;
      if (c && retryCount.current < 2) {
        retryCount.current++;
        const offset = a.currentTime;
        notify('连接中断，正在重新连接…');
        void openRef.current(c.book, c.chapter, offset, true);
      } else if (c) notify('播放失败，请重新播放或尝试其它作品');
    };
    const onWaiting = () => setLoading(true);
    const onCanPlay = () => setLoading(false);
    const onSeeked = () => save();
    const events = { play: onPlay, pause: onPause, timeupdate: onTime, durationchange: onDuration,
      ended: onEnded, error: onError, waiting: onWaiting, canplay: onCanPlay, seeked: onSeeked };
    Object.entries(events).forEach(([key, fn]) => a.addEventListener(key, fn));
    window.addEventListener('beforeunload', save);
    const unsub = window.abts.onFlush(save);
    const unsubPlayback = window.abts.onTogglePlayback(() => toggleRef.current());
    if ('mediaSession' in navigator) {
      for (const [action, handler] of Object.entries({
        play: () => a.play().catch(e => notify(e.message)), pause: () => a.pause(),
        previoustrack: () => nextRef.current(-1), nexttrack: () => nextRef.current(1),
        seekbackward: () => { a.currentTime = Math.max(0, a.currentTime - 15); },
        seekforward: () => { a.currentTime = Math.min(a.duration || Infinity, a.currentTime + 15); },
        seekto: e => { a.currentTime = e.seekTime; }
      })) { try { navigator.mediaSession.setActionHandler(action, handler); } catch {} }
    }
    return () => {
      save(); unsub(); unsubPlayback();
      Object.entries(events).forEach(([key, fn]) => a.removeEventListener(key, fn));
      window.removeEventListener('beforeunload', save);
    };
  }, []);
  useEffect(() => {
    audio.current.playbackRate = state?.settings.rate || 1;
    audio.current.volume = state?.settings.volume ?? 0.8;
  }, [state?.settings.rate, state?.settings.volume]);
  useEffect(() => {
    if (!deadline) { setRemaining(0); return; }
    const tick = () => {
      setRemaining(Math.max(0, Math.ceil((deadline - Date.now()) / 1000)));
      if (Date.now() >= deadline) {
        audio.current.pause(); setDeadline(null); notify('睡眠定时已结束');
      }
    };
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [deadline]);
  toggleRef.current = () => {
      const a = audio.current;
      if (!track) {
        const saved = stateRef.current?.current;
        const book = stateRef.current?.books?.[saved?.bvid];
        const chapter = book?.chapters?.find(c => c.cid === saved.cid);
        if (chapter) return open(book, chapter);
        return;
      }
      if (a.paused) {
        if ((!a.getAttribute('src') || a.error) && track) return open(track.book, track.chapter, a.currentTime);
        a.play().catch(e => notify(e.message));
      } else a.pause();
  };
  return {
    track, playing, loading, position, duration, offline, remaining,
    open, next, save, toggle: () => toggleRef.current(),
    seek: value => { if (current.current) { audio.current.currentTime = Math.min(Math.max(0, value), duration || Infinity); setPosition(value); } },
    sleep: minutes => setDeadline(minutes ? Date.now() + minutes * 60000 : null)
  };
}
