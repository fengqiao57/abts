import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import {
  Headphones, Compass, Library, History, Download, Users, Settings, Search, ArrowLeft,
  Play, Pause, SkipBack, SkipForward, RotateCcw, RotateCw, Volume2, VolumeX, Heart,
  ListMusic, Moon, X, Plus, Check, ExternalLink, FolderOpen, Upload, LogIn, LogOut,
  ChevronRight, ChevronDown, RefreshCw, Trash2, AlertCircle, LoaderCircle, ArrowDown,
  Sun, Monitor, Keyboard, EyeOff, BookOpen, WifiOff, Clock3, CheckCircle2, UserRound
} from 'lucide-react';
import { usePlayer } from './player';
import './styles.css';
import './diagnostics';

const api = window.abts;
const categories = [
  ['热门推荐', '有声小说'], ['广播剧', '广播剧 全集'], ['评书', '评书 单田芳'],
  ['相声', '相声 德云社'], ['悬疑', '悬疑有声小说'], ['玄幻仙侠', '玄幻小说听书'], ['名著悦读', '世界名著朗读']
];
const anchors = [['周建龙','鬼吹灯 · 盗墓笔记'],['紫襟','悬疑 · 都市'],['单田芳','隋唐演义 · 白眉大侠'],['郭德纲','相声 · 评书'],['王明军','三体 · 经典文学'],['729声工场','广播剧 · 多人演播']];
const speeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3];
const prettyShortcut = s => (s || '').replace(/Control/g, 'Ctrl').replace(/\+/g, ' + ');
function time(seconds) {
  seconds = Math.max(0, Math.floor(Number(seconds) || 0));
  const h = Math.floor(seconds / 3600);
  return `${h ? h + ':' : ''}${h ? String(Math.floor(seconds / 60) % 60).padStart(2, '0') : Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}
function hours(s) { return s >= 3600 ? `${(s / 3600).toFixed(1)} 小时` : `${Math.max(1, Math.round(s / 60))} 分钟`; }
function bytes(n) { return n > 1024 ** 3 ? `${(n / 1024 ** 3).toFixed(1)} GB` : `${(n / 1024 ** 2).toFixed(1)} MB`; }
function percentage(state, book) {
  const history = state.history[book.bvid];
  if (!history) return 0;
  const total = book.chapters?.reduce((s, c) => s + c.duration, 0) || book.duration || 1;
  const listened = Object.values(history.chapters || {}).reduce((s, p) => s + Math.min(p.position || 0, p.duration || 0), 0);
  return Math.min(100, Math.floor(listened / total * 100));
}
function IconButton({ icon: Icon, title, children, className = '', ...props }) {
  return <button type="button" className={`icon-button ${className}`} title={title} aria-label={title} {...props}><Icon size={19}/>{children}</button>;
}
function Cover({ book, className = '' }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [book?.pic]);
  return <div className={`cover ${className}`}>
    {book?.pic && !failed ? <img src={book.pic} alt="" loading="lazy" referrerPolicy="no-referrer" onError={() => setFailed(true)}/>
      : <div className="cover-fallback"><Headphones size={30}/><span>{book?.title?.slice(0, 10) || '阿B听书'}</span></div>}
  </div>;
}
function Empty({ icon: Icon = BookOpen, title, action, onAction }) {
  return <div className="empty"><Icon size={36} strokeWidth={1.3}/><h3>{title}</h3>
    {action && <button className="button primary" onClick={onAction}>{action}<ChevronRight size={16}/></button>}</div>;
}
function App() {
  const [state, setState] = useState(null);
  const [view, setView] = useState({ name: 'discover', category: 0 });
  const [stack, setStack] = useState([]);
  const [input, setInput] = useState('');
  const [result, setResult] = useState({ items: [], hasMore: false });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [page, setPage] = useState(1);
  const [reload, setReload] = useState(0);
  const [toast, setToast] = useState('');
  const [modal, setModal] = useState(null);
  const [drawer, setDrawer] = useState(false);
  const [user, setUser] = useState(null);
  const [shortcutStatus, setShortcutStatus] = useState({ active: '', error: '' });
  const queryId = useRef(0);
  const notify = message => setToast(String(message).replace(/^Error invoking remote method '[^']+': Error: /, ''));
  const player = usePlayer(state, notify);
  const go = next => { setStack(s => [...s, view]); setView(next); setError(''); };
  const back = () => { setView(stack.at(-1) || { name: 'discover', category: 0 }); setStack(s => s.slice(0, -1)); };
  async function task(fn) { try { return await fn(); } catch (e) { notify(e.message); } }
  useEffect(() => {
    const update = data => {
      if (data.shortcutStatus) setShortcutStatus(data.shortcutStatus);
      setState(data);
    };
    api.state().then(update).catch(e => notify(e.message));
    const unsub = api.subscribe(update);
    api.user().then(setUser).catch(() => {});
    return unsub;
  }, []);
  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(() => setToast(''), 5500);
    return () => clearTimeout(timer);
  }, [toast]);
  useEffect(() => {
    const media = matchMedia('(prefers-color-scheme: dark)');
    const apply = () => document.documentElement.dataset.theme = state?.settings.theme === 'system' ? media.matches ? 'dark' : 'light' : state?.settings.theme || 'light';
    apply(); media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, [state?.settings.theme]);
  useEffect(() => {
    const onKey = e => {
      if (e.code === 'Space' && !['INPUT', 'SELECT', 'TEXTAREA', 'BUTTON'].includes(e.target.tagName) && !modal) {
        e.preventDefault(); if (player.track) player.toggle();
      }
      if (e.key === 'Escape') { setModal(null); setDrawer(false); }
      if (e.ctrlKey && e.key.toLowerCase() === 'f') { e.preventDefault(); document.querySelector('#search')?.focus(); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [player.track, modal]);
  useEffect(() => {
    if (!['discover', 'search', 'up'].includes(view.name)) return;
    const id = ++queryId.current;
    setBusy(true); setError(''); setResult({ items: [], hasMore: false }); setPage(1);
    const promise = view.name === 'up' ? api.userBooks(view.user, 1) :
      api.search(view.name === 'discover' ? categories[view.category || 0][1] : view.query, 1,
        view.type || 'video', view.name === 'discover' && !view.category ? 'click' : '');
    promise.then(data => { if (id === queryId.current) setResult(data); })
      .catch(e => { if (id === queryId.current) setError(e.message); })
      .finally(() => { if (id === queryId.current) setBusy(false); });
    return () => { queryId.current++; };
  }, [view.name, view.category, view.query, view.type, view.user?.mid, reload]);
  async function loadMore() {
    if (busy) return;
    const id = queryId.current;
    setBusy(true);
    try {
      const data = view.name === 'up' ? await api.userBooks(view.user, page + 1) :
        await api.search(view.name === 'discover' ? categories[view.category || 0][1] : view.query,
          page + 1, view.type || 'video', view.name === 'discover' && !view.category ? 'click' : '');
      if (id !== queryId.current) return;
      setResult(prev => ({ ...data, items: [...prev.items, ...data.items.filter(item =>
        !prev.items.some(old => (old.bvid || old.mid) === (item.bvid || item.mid)))] }));
      setPage(p => p + 1); setError('');
    } catch (e) { if (id === queryId.current) notify(e.message); }
    finally { if (id === queryId.current) setBusy(false); }
  }
  async function detail(book, autoPlay = false) {
    try {
      if (autoPlay && book.chapters?.length) return resume(book);
      const data = await api.detail(typeof book === 'string' ? book : book.bvid);
      go({ name: 'book', book: data });
      if (autoPlay) resume(data);
    } catch (e) { notify(e.message); }
  }
  function resume(book) {
    const cid = state.history[book.bvid]?.cid;
    player.open(book, book.chapters.find(c => c.cid === cid) || book.chapters[0]);
  }
  function search(value = input) {
    value = value.trim();
    if (!value) return;
    const bv = value.match(/BV[0-9A-Za-z]{10}/)?.[0];
    if (bv) { detail(bv); return; }
    go({ name: 'search', query: value, type: 'video' });
    setInput(value);
  }
  async function toggleFavorite(book) {
    await task(() => api.favorite(book.bvid, !state.favorites.includes(book.bvid)));
  }
  async function setShortcut(value, action = 'hide') {
    await api.shortcut(value, action);
    setShortcutStatus(prev => ({ ...prev, ...(action === 'hide'
      ? { active: value, error: '' } : { playbackActive: value, playbackError: '' }) }));
    notify(`全局快捷键已设为 ${prettyShortcut(value)}`);
  }
  if (!state) return <div className="boot"><img src="../assets/logo.png"/><LoaderCircle className="spin"/><p>正在打开书库</p></div>;
  const historyIds = Object.keys(state.history).sort((a, b) => state.history[b].updated - state.history[a].updated);
  const recent = historyIds.map(id => state.books[id]).filter(Boolean);
  const pending = state.downloads.filter(t => ['queued', 'downloading'].includes(t.status)).length;
  const viewTitles = { discover: '发现好声音', shelf: '我的书架', history: '最近收听', downloads: '离线缓存', follows: '关注的 UP 主', settings: '设置', search: '搜索', up: view.user?.name, book: '作品详情' };
  const books = view.name === 'shelf' ? state.favorites.map(id => state.books[id]).filter(Boolean) : view.name === 'history' ? recent : result.items;
  const renderCards = list => <div className="book-grid">{list.map(book => <article className="book-card" key={book.bvid}>
    <button className="book-art" onClick={() => detail(book)} title={book.title}><Cover book={book}/><span className="art-play"><Play size={20} fill="currentColor"/></span><span className="duration-badge">{hours(book.duration)}</span></button>
    <button className="book-title" onClick={() => detail(book)} title={book.title}>{book.title}</button>
    <div className="book-meta"><span>{book.author}</span>{book.pages > 1 && <span>{book.pages} 集</span>}</div>
    {state.history[book.bvid] && <button className="book-progress" onClick={() => detail(book, true)}><span><i style={{ width: `${percentage(state, book)}%` }}/></span><small>已听 {percentage(state, book)}%</small><Play size={12}/></button>}
  </article>)}</div>;
  return <div className="app-shell">
    <aside className="sidebar">
      <button className="brand" onClick={() => go({ name: 'discover', category: 0 })}><img src="../assets/logo.png" alt="阿B听书"/><span>阿B听书<small>桌面版</small></span></button>
      <div className="nav-label">我的听书空间</div>
      <nav>{[
        ['discover', Compass, '发现', null], ['shelf', Library, '书架', state.favorites.length],
        ['history', History, '最近收听', null], ['downloads', Download, '离线缓存', pending || null],
        ['follows', Users, '我的关注', null]
      ].map(([name, Icon, label, count]) => <button key={name} className={`nav-item ${view.name === name ? 'active' : ''}`} onClick={() => go({ name, category: 0 })}>
        <Icon size={19}/><span>{label}</span>{count != null && <small>{count}</small>}</button>)}</nav>
      <div className="sidebar-bottom">
        <button className={`nav-item ${view.name === 'settings' ? 'active' : ''}`} onClick={() => go({ name: 'settings' })}><Settings size={18}/><span>设置</span></button>
        <button className="account" onClick={() => user?.loggedIn ? go({ name: 'settings' }) : setModal('login')}>
          <span className="avatar">{user?.face ? <img src={user.face} referrerPolicy="no-referrer" alt=""/> : <UserRound size={20}/>}</span>
          <span>{user?.loggedIn ? user.name : '游客'}<small>{user?.loggedIn ? '哔哩哔哩账号' : '扫码登录'}</small></span><ChevronRight size={15}/>
        </button>
      </div>
    </aside>
    <div className="workspace">
      <header className="topbar">
        <IconButton icon={ArrowLeft} title="返回" disabled={!stack.length} onClick={back}/>
        <form className="search-box" onSubmit={e => { e.preventDefault(); search(); }}><Search size={18}/><input id="search" aria-label="搜索书名、主播或粘贴 BV 链接" placeholder="搜索书名、主播，或粘贴 B 站链接" value={input} onChange={e => setInput(e.target.value)}/>{input && <IconButton icon={X} title="清空搜索" onClick={() => setInput('')}/>}</form>
        <div className="top-actions">
          <IconButton icon={EyeOff} title={`隐藏窗口 · ${prettyShortcut(shortcutStatus.active || state.settings.hideShortcut)}`} onClick={() => task(() => api.toggleHidden())}/>
          <IconButton icon={state.settings.theme === 'dark' ? Sun : Moon} title="切换外观" onClick={() => task(() => api.settings({ theme: document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark' }))}/>
        </div>
      </header>
      <main key={view.name + (view.book?.bvid || '')} className="content">
        {view.name === 'book' ? <BookDetail book={state.books[view.book.bvid] || view.book} state={state} player={player}
          onPlay={resume} onFavorite={toggleFavorite} onUser={u => go({ name: 'up', user: u })}
          onDownload={cids => task(async () => { await api.download(view.book.bvid, cids); notify(`${cids.length} 集已加入缓存队列`); })}
          onExternal={() => task(() => api.external(`https://www.bilibili.com/video/${view.book.bvid}`))}/>
          : view.name === 'settings' ? <SettingsPage state={state} shortcutStatus={shortcutStatus} user={user}
            task={task} notify={notify} setShortcut={setShortcut} login={() => setModal('login')}
            logout={() => task(async () => { await api.logout(); setUser(null); notify('已退出登录'); })}/>
          : view.name === 'downloads' ? <DownloadsPage state={state} onDetail={detail} task={task} player={player}/>
          : view.name === 'follows' ? <>
            <PageHeading title="我的关注" subtitle={`${state.follows.length} 位 UP 主`}/>
            {state.follows.length ? <UserList users={state.follows} state={state} task={task} onUser={u => go({ name: 'up', user: u })}/>
              : <Empty icon={Users} title="还没有关注的 UP 主" action="搜索主播" onAction={() => { document.querySelector('#search')?.focus(); }}/>}
          </> : <>
            <PageHeading title={view.name === 'search' ? `“${view.query}”` : viewTitles[view.name]}
              subtitle={view.name === 'discover' ? '给眼睛放个假，把故事交给耳朵。' : view.name === 'shelf' ? `${books.length} 本收藏` : view.name === 'history' ? `${books.length} 本收听记录` : view.name === 'up' ? '公开投稿' : '搜索结果'}
              action={['discover','search','up'].includes(view.name) && <IconButton icon={RefreshCw} title="刷新" disabled={busy} onClick={() => setReload(n => n + 1)}/>}/>
            {view.name === 'discover' && <>
              <div className="category-tabs">{categories.map(([label], index) => <button className={index === (view.category || 0) ? 'selected' : ''} key={label} onClick={() => setView(v => ({ ...v, category: index }))}>{label}</button>)}</div>
              {recent[0] && <div className="continue-strip"><Cover book={recent[0]}/><div><small>接着上次的故事</small><b>{recent[0].title}</b><span>{state.books[recent[0].bvid].chapters?.find(c => c.cid === state.history[recent[0].bvid].cid)?.title}</span></div><button className="button primary" onClick={() => resume(recent[0])}><Play size={15} fill="currentColor"/>继续收听</button></div>}
              <div className="section-heading"><h2>精选主播</h2><span>熟悉的声音，好听的故事</span></div>
              <div className="anchors">{anchors.map(([name, works], index) => <button key={name} onClick={() => search(`${name} ${index === 2 ? '评书' : index === 3 ? '相声' : '有声小说'}`)}><span className={`anchor-icon color-${index}`}><Headphones size={20}/></span><span><b>{name}</b><small>{works}</small></span><ChevronRight size={14}/></button>)}</div>
              <div className="section-heading"><h2>{categories[view.category || 0][0]}</h2><span>{result.items.length ? `${result.items.length} 部作品` : '来自哔哩哔哩的公开音频'}</span></div>
            </>}
            {view.name === 'search' && <div className="category-tabs compact">{[['video','听书'],['user','UP 主']].map(([type,label]) => <button key={type} className={(view.type || 'video') === type ? 'selected' : ''} onClick={() => setView(v => ({ ...v, type }))}>{label}</button>)}</div>}
            {view.name === 'up' && <div className="up-toolbar"><button className="button" onClick={() => task(() => api.follow(view.user, !state.follows.some(u => u.mid === view.user.mid)))}>{state.follows.some(u => u.mid === view.user.mid) ? <Check size={16}/> : <Plus size={16}/>} {state.follows.some(u => u.mid === view.user.mid) ? '已关注' : '关注'}</button><button className="button" onClick={() => task(() => api.external(`https://space.bilibili.com/${view.user.mid}`))}><ExternalLink size={16}/>B 站主页</button></div>}
            {busy && !result.items.length && ['discover','search','up'].includes(view.name) ? <div className="loading-state"><LoaderCircle className="spin" size={24}/><span>正在寻找好声音…</span></div>
              : error ? <div className="error-state"><WifiOff size={32}/><h3>暂时没能加载内容</h3><p>{error}</p><button className="button" onClick={() => setReload(n => n + 1)}><RefreshCw size={15}/>重试</button><button className="text-button" onClick={() => go({ name: 'downloads' })}>收听离线缓存</button></div>
              : view.name === 'search' && view.type === 'user' ? <UserList users={result.items} state={state} task={task} onUser={u => go({ name: 'up', user: u })}/>
              : books.length ? renderCards(books)
              : <Empty title={view.name === 'shelf' ? '书架还空着，先找一本喜欢的' : view.name === 'history' ? '故事从第一次播放开始' : '这一页没有找到符合条件的有声内容'} action={['shelf','history'].includes(view.name) ? '去发现' : undefined} onAction={() => go({ name: 'discover', category: 0 })}/>}
            {result.hasMore && ['discover','search','up'].includes(view.name) && !error && <div className="load-more"><button className="button" disabled={busy} onClick={loadMore}>{busy ? <LoaderCircle className="spin" size={16}/> : <ArrowDown size={16}/>}加载更多</button></div>}
            {view.name === 'search' && !busy && !result.items.length && !error && <div className="empty-hint">也可以在搜索框粘贴作品的 BV 号或完整链接。</div>}
          </>}
      </main>
    </div>
    <footer className={`player-bar ${!player.track ? 'idle' : ''}`}>
      <button className="now-playing" disabled={!player.track} onClick={() => setDrawer(d => !d)}><Cover book={player.track?.book}/><span><b>{player.track?.book.title || '阿B听书'}</b><small>{player.track?.chapter.title || '还没有正在播放的故事'}</small></span>{player.offline && player.track && <Download size={14} className="offline-icon"/>}</button>
      <div className="transport">
        <div className="transport-buttons">
          <IconButton icon={RotateCcw} title="后退 15 秒" disabled={!player.track} onClick={() => player.seek(player.position - 15)}><small>15</small></IconButton>
          <IconButton icon={SkipBack} title="上一集" disabled={!player.track} onClick={() => player.next(-1)}/>
          <IconButton icon={player.loading ? LoaderCircle : player.playing ? Pause : Play} title={player.playing ? '暂停' : '播放'} disabled={!player.track} className={`play-button ${player.loading ? 'spin-icon' : ''}`} onClick={player.toggle}/>
          <IconButton icon={SkipForward} title="下一集" disabled={!player.track} onClick={() => player.next(1)}/>
          <IconButton icon={RotateCw} title="前进 15 秒" disabled={!player.track} onClick={() => player.seek(player.position + 15)}><small>15</small></IconButton>
        </div>
        <div className="scrubber"><span>{time(player.position)}</span><input type="range" aria-label="播放进度" min="0" max={player.duration || 1} step="1" value={Math.min(player.position, player.duration || 1)} disabled={!player.track} onChange={e => player.seek(Number(e.target.value))} style={{ '--progress': `${player.duration ? player.position / player.duration * 100 : 0}%` }}/><span>{time(player.duration)}</span></div>
      </div>
      <div className="player-tools">
        <select className="rate-select" aria-label="播放倍速" value={state.settings.rate} onChange={e => task(() => api.settings({ rate: Number(e.target.value) }))}>{speeds.map(s => <option key={s} value={s}>{s}×</option>)}</select>
        <IconButton icon={Moon} title="睡眠定时" className={player.remaining ? 'accent' : ''} onClick={() => setModal('sleep')}>{player.remaining > 0 && <span className="timer-dot"/>}</IconButton>
        <div className="volume"><IconButton icon={state.settings.volume ? Volume2 : VolumeX} title="静音 / 恢复音量" onClick={() => task(() => api.settings({ volume: state.settings.volume ? 0 : 0.8 }))}/><input type="range" aria-label="音量" min="0" max="1" step="0.01" value={state.settings.volume} onChange={e => task(() => api.settings({ volume: Number(e.target.value) }))}/></div>
        <IconButton icon={ListMusic} title="正在播放与目录" disabled={!player.track} className={drawer ? 'accent' : ''} onClick={() => setDrawer(v => !v)}/>
      </div>
    </footer>
    {drawer && player.track && <aside className="playing-drawer">
      <div className="drawer-heading"><h2>正在收听</h2><IconButton icon={X} title="关闭播放面板" onClick={() => setDrawer(false)}/></div>
      <button className="drawer-art" onClick={() => { detail(player.track.book); setDrawer(false); }}><Cover book={player.track.book}/></button>
      <h3>{player.track.book.title}</h3><p>{player.track.book.author}</p>
      <div className="drawer-options"><label><input type="checkbox" checked={state.settings.stopAfter} onChange={e => task(() => api.settings({ stopAfter: e.target.checked }))}/>播完本集暂停</label><IconButton icon={Heart} title="收藏作品" className={state.favorites.includes(player.track.book.bvid) ? 'favorited' : ''} onClick={() => toggleFavorite(player.track.book)}/></div>
      <div className="drawer-chapters">{player.track.book.chapters.map(ch => <button key={ch.cid} className={ch.cid === player.track.chapter.cid ? 'current' : ''} onClick={() => player.open(player.track.book, ch)}><span>{ch.index + 1}</span><b>{ch.title}</b><small>{time(ch.duration)}</small></button>)}</div>
    </aside>}
    {modal && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setModal(null); }}><div className="modal" role="dialog" aria-modal="true"><IconButton className="modal-close" icon={X} title="关闭" onClick={() => setModal(null)}/>
      {modal === 'login' ? <LoginModal notify={notify} onSuccess={u => { setUser(u); setModal(null); notify('登录成功'); }}/>
        : <SleepModal player={player} close={() => setModal(null)}/>}
    </div></div>}
    {toast && <div role="status" className="toast"><AlertCircle size={17}/><span>{toast}</span><IconButton icon={X} title="关闭提示" onClick={() => setToast('')}/></div>}
  </div>;
}
function PageHeading({ title, subtitle, action }) {
  return <div className="page-heading"><div><h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</div>{action}</div>;
}
function BookDetail({ book, state, player, onPlay, onFavorite, onDownload, onExternal, onUser }) {
  const [selected, setSelected] = useState([]);
  const [filter, setFilter] = useState('');
  const [descending, setDescending] = useState(false);
  const [batch, setBatch] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const chapters = book.chapters || [];
  const filtered = chapters.filter(c => c.title.toLowerCase().includes(filter.toLowerCase()));
  const shown = descending ? [...filtered].reverse() : filtered;
  const current = player.track?.book.bvid === book.bvid ? player.track.chapter.cid : null;
  return <>
    <div className="book-detail">
      <Cover book={book}/>
      <div className="book-info"><span className="eyebrow">有声作品</span><h1>{book.title}</h1>
        <button className="author-link" onClick={() => onUser({ mid: book.mid, name: book.author, face: '' })}><UserRound size={15}/>{book.author}<ChevronRight size={14}/></button>
        <div className="detail-meta"><span>{chapters.length} 集</span><span>{hours(book.duration)}</span><span>{book.play >= 10000 ? `${(book.play / 10000).toFixed(1)} 万` : book.play} 次播放</span></div>
        <div className={`description ${expanded ? 'expanded' : ''}`}>{book.desc || '暂无作品简介'}</div>{book.desc?.length > 120 && <button className="text-button" onClick={() => setExpanded(v => !v)}>{expanded ? '收起' : '展开简介'}</button>}
        <div className="detail-actions"><button className="button primary" onClick={() => onPlay(book)}><Play size={17} fill="currentColor"/>{state.history[book.bvid] ? '继续收听' : '开始收听'}</button>
          <button className={`button ${state.favorites.includes(book.bvid) ? 'favorited' : ''}`} onClick={() => onFavorite(book)}><Heart size={17} fill={state.favorites.includes(book.bvid) ? 'currentColor' : 'none'}/>{state.favorites.includes(book.bvid) ? '已收藏' : '加入书架'}</button>
          <IconButton icon={ExternalLink} title="打开原作品" onClick={onExternal}/></div>
      </div>
    </div>
    <div className="chapter-heading"><h2>章节目录 <small>{chapters.length}</small></h2><div>
      <label className="chapter-search"><Search size={15}/><input placeholder="查找章节" aria-label="查找章节" value={filter} onChange={e => setFilter(e.target.value)}/></label>
      <button className="button small" onClick={() => setDescending(d => !d)}><ArrowDown size={15}/>{descending ? '倒序' : '正序'}</button>
      <button className="button small" onClick={() => { setBatch(v => !v); setSelected([]); }}><Download size={15}/>{batch ? '取消选择' : '批量缓存'}</button>
    </div></div>
    {batch && <div className="batch-bar"><label><input type="checkbox" checked={filtered.length > 0 && filtered.every(c => selected.includes(c.cid))} onChange={e => setSelected(e.target.checked ? filtered.map(c => c.cid) : [])}/>全选当前列表</label><span>已选 {selected.length} 集</span><button className="button primary small" disabled={!selected.length} onClick={() => { onDownload(selected); setBatch(false); setSelected([]); }}><Download size={15}/>缓存所选</button></div>}
    <div className="chapter-table"><div className="chapter-table-head"><span>#</span><span>章节名称</span><span>时长</span><span>缓存</span></div>
      {shown.map(c => {
        const progress = state.history[book.bvid]?.chapters?.[c.cid];
        const done = progress?.position >= (progress?.duration || c.duration) - 2;
        const task = state.downloads.find(t => t.bvid === book.bvid && t.cid === c.cid);
        return <div key={c.cid} className={`chapter-row ${current === c.cid ? 'current' : ''} ${done ? 'listened' : ''}`}>
          {batch ? <input aria-label={`选择 ${c.title}`} type="checkbox" checked={selected.includes(c.cid)} onChange={e => setSelected(prev => e.target.checked ? [...prev, c.cid] : prev.filter(id => id !== c.cid))}/>
            : <span className="chapter-index">{current === c.cid && player.playing ? <Volume2 size={16}/> : done ? <Check size={15}/> : c.index + 1}</span>}
          <button className="chapter-name" onClick={() => player.open(book, c)}>{c.title}{progress && !done && <small>已听 {time(progress.position)}</small>}</button>
          <span className="chapter-time">{time(c.duration)}</span>
          <IconButton icon={task?.status === 'done' ? CheckCircle2 : ['downloading','queued'].includes(task?.status) ? LoaderCircle : Download} title={task?.status === 'done' ? '已缓存' : '缓存本集'} disabled={task?.status === 'done' || ['downloading','queued'].includes(task?.status)} onClick={() => onDownload([c.cid])}/>
        </div>;
      })}{!shown.length && <Empty title="没有匹配的章节"/>}
    </div>
  </>;
}
function UserList({ users, state, task, onUser }) {
  if (!users.length) return <Empty icon={Users} title="没有找到 UP 主"/>;
  return <div className="user-list">{users.map(u => <div className="user-row" key={u.mid}><button className="user-person" onClick={() => onUser(u)}><span className="avatar">{u.face ? <img src={u.face} alt="" referrerPolicy="no-referrer"/> : <UserRound size={22}/>}</span><span><b>{u.name}</b><small>{u.sign || (u.fans ? `${u.fans} 位粉丝` : 'UP 主')}</small></span></button><button className="button small" onClick={() => task(() => api.follow(u, !state.follows.some(f => f.mid === u.mid)))}>{state.follows.some(f => f.mid === u.mid) ? <Check size={15}/> : <Plus size={15}/>}{state.follows.some(f => f.mid === u.mid) ? '已关注' : '关注'}</button></div>)}</div>;
}
function DownloadsPage({ state, onDetail, task, player }) {
  const [filter, setFilter] = useState('all');
  const tasks = state.downloads.filter(t => filter === 'all' || t.status === filter);
  const groups = [...new Set(tasks.map(t => t.bvid))];
  const size = state.downloads.filter(t => t.status === 'done').reduce((n, t) => n + t.received, 0);
  const [confirmId, setConfirmId] = useState(null);
  return <>
    <PageHeading title="离线缓存" subtitle={`${state.downloads.filter(t => t.status === 'done').length} 集已缓存 · ${bytes(size)}`} action={<button className="button" onClick={() => task(() => api.openData())}><FolderOpen size={16}/>打开目录</button>}/>
    <div className="category-tabs">{[['all','全部'],['done','已完成'],['downloading','正在缓存'],['queued','等待中'],['failed','失败']].map(([value,label]) => <button key={value} className={filter === value ? 'selected' : ''} onClick={() => setFilter(value)}>{label}</button>)}</div>
    {!groups.length ? <Empty icon={Download} title="暂无缓存章节"/> : groups.map(id => {
      const book = state.books[id];
      return <section className="download-group" key={id}><button className="download-book" onClick={() => onDetail(book)}><Cover book={book}/><span><b>{book?.title}</b><small>{book?.author}</small></span><ChevronRight size={17}/></button>
        {tasks.filter(t => t.bvid === id).sort((a, b) => a.index - b.index).map(t => <div className="download-row" key={t.id}><span className={`status-icon ${t.status}`}>{t.status === 'done' ? <CheckCircle2 size={18}/> : t.status === 'failed' ? <AlertCircle size={18}/> : <LoaderCircle size={18} className={t.status === 'downloading' ? 'spin' : ''}/>}</span>
          <div className="download-info"><b>{t.title}</b><small>{t.status === 'done' ? bytes(t.received) : t.status === 'failed' ? t.error : t.status === 'queued' ? '等待缓存' : `${bytes(t.received)} / ${t.total ? bytes(t.total) : '未知大小'}`}</small>{t.status === 'downloading' && <progress max={t.total || 1} value={t.received}/>}</div>
          {t.status === 'done' && <IconButton icon={Play} title={`播放 ${t.title}`} onClick={() => player.open(book, book.chapters.find(c => c.cid === t.cid))}/>}
          {t.status === 'failed' && <IconButton icon={RefreshCw} title="重试缓存" onClick={() => task(() => api.retry(t.id))}/>}
          {confirmId === t.id ? <><button className="text-button danger" onClick={() => { task(() => api.removeDownload(t.id)); setConfirmId(null); }}>确认移除</button><IconButton icon={X} title="取消移除" onClick={() => setConfirmId(null)}/></> : <IconButton icon={Trash2} title="移除缓存" onClick={() => setConfirmId(t.id)}/>}
        </div>)}</section>;
    })}
  </>;
}
function SettingsPage({ state, shortcutStatus, user, task, notify, setShortcut, login, logout }) {
  const [recording, setRecording] = useState(null);
  const [keyError, setKeyError] = useState('');
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    if (!recording) return;
    const handler = async e => {
      e.preventDefault(); e.stopPropagation();
      if (e.key === 'Escape') { setRecording(null); return; }
      if (['Control','Alt','Shift','Meta'].includes(e.key) || e.repeat) return;
      const key = e.code.startsWith('Key') ? e.code.slice(3) : e.code.startsWith('Digit') ? e.code.slice(5) : /^F\d{1,2}$/.test(e.key) ? e.key : null;
      if (!key || !(e.ctrlKey || e.altKey || e.shiftKey || e.metaKey)) { setKeyError('请使用修饰键加字母、数字或 F1–F24'); return; }
      const combo = [e.ctrlKey && 'Control', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Super', key].filter(Boolean).join('+');
      setSaving(true);
      try { await setShortcut(combo, recording); setRecording(null); setKeyError(''); } catch (error) { setKeyError(error.message); }
      finally { setSaving(false); }
    };
    window.addEventListener('keydown', handler, true);
    return () => window.removeEventListener('keydown', handler, true);
  }, [recording, setShortcut]);
  return <>
    <PageHeading title="设置" subtitle="按自己的习惯，安心听书。"/>
    <section className="settings-section"><h2><Keyboard size={18}/>全局快捷键</h2>
      {[
        ['hide', '隐藏', '隐藏 / 取消隐藏', '取消隐藏后仅恢复任务栏，保持最小化', 'hideShortcut', 'Control+Alt+H', shortcutStatus.active, shortcutStatus.error],
        ['playback', '播放', '播放 / 暂停', '全局生效，隐藏时可用', 'playbackShortcut', 'Control+Alt+P', shortcutStatus.playbackActive, shortcutStatus.playbackError]
      ].map(([action, label, title, description, setting, defaultKey, active, error]) => <React.Fragment key={action}>
        <div className="setting-row"><div><b>{title}</b><small>{description}</small><small className={active ? 'success-text' : 'danger'}>{active ? '已注册' : error || '未注册'}</small></div>
          <div className="row-actions"><button className={`shortcut-recorder ${recording === action ? 'recording' : ''}`} disabled={saving} onClick={() => { setRecording(v => v === action ? null : action); setKeyError(''); }} aria-label={`设置${label}快捷键`}>{recording === action ? '请按下快捷键…' : prettyShortcut(state.settings[setting])}</button>
            <IconButton icon={RotateCcw} title={`恢复默认${label}快捷键`} disabled={saving} onClick={() => task(async () => { await setShortcut(defaultKey, action); setRecording(null); setKeyError(''); })}/></div>
        </div>
      </React.Fragment>)}
      {keyError && <div className="inline-error"><AlertCircle size={16}/>{keyError}</div>}
    </section>
    <section className="settings-section"><h2><Sun size={18}/>外观与播放</h2>
      <div className="setting-row"><b>外观模式</b><div className="segmented">{[['light',Sun,'浅色'],['dark',Moon,'深色'],['system',Monitor,'系统']].map(([value,Icon,label]) => <button key={value} className={state.settings.theme === value ? 'selected' : ''} onClick={() => task(() => api.settings({ theme: value }))}><Icon size={15}/>{label}</button>)}</div></div>
      <div className="setting-row"><b>默认倍速</b><select aria-label="默认倍速" value={state.settings.rate} onChange={e => task(() => api.settings({ rate: Number(e.target.value) }))}>{speeds.map(s => <option key={s} value={s}>{s}×</option>)}</select></div>
      <div className="setting-row"><b>播完本集自动暂停</b><input type="checkbox" className="toggle" aria-label="播完本集自动暂停" checked={state.settings.stopAfter} onChange={e => task(() => api.settings({ stopAfter: e.target.checked }))}/></div>
    </section>
    <section className="settings-section"><h2><UserRound size={18}/>账号</h2><div className="setting-row"><div><b>{user?.loggedIn ? user.name : '尚未登录'}</b><small>哔哩哔哩</small></div><button className="button" onClick={user?.loggedIn ? logout : login}>{user?.loggedIn ? <LogOut size={16}/> : <LogIn size={16}/>}{user?.loggedIn ? '退出登录' : '扫码登录'}</button></div></section>
    <section className="settings-section"><h2><FolderOpen size={18}/>本地数据</h2>
      <div className="setting-row"><div><b>书架与收听进度</b><small>导入时合并书架，保留更新的收听记录</small></div><div className="row-actions"><button className="button small" onClick={() => task(async () => { if (await api.export()) notify('书架备份已导出'); })}><Upload size={15}/>导出备份</button><button className="button small" onClick={() => task(async () => { if (await api.import()) notify('备份已合并'); })}><Download size={15}/>导入备份</button></div></div>
      <div className="setting-row"><span>数据与音频缓存目录</span><button className="button small" onClick={() => task(() => api.openData())}><FolderOpen size={15}/>打开目录</button></div>
      <div className="setting-row"><span>诊断日志</span><button className="button small" onClick={() => task(() => api.openLogs())}><FolderOpen size={15}/>打开日志目录</button></div>
    </section>
    <section className="settings-section about"><h2><Headphones size={18}/>关于阿B听书</h2><p>阿B听书 · 桌面版 1.0.2</p><p>基于 fengqiao57/abts（MIT）制作的独立桌面版本。非哔哩哔哩官方产品，音频与图文版权归原作者所有，请支持正版。</p><button className="text-button" onClick={() => task(() => api.external('https://github.com/fengqiao57/abts'))}>原项目与开源许可 <ExternalLink size={14}/></button></section>
  </>;
}
function LoginModal({ notify, onSuccess }) {
  const [qr, setQr] = useState(null);
  const [status, setStatus] = useState('正在生成二维码…');
  const [refresh, setRefresh] = useState(0);
  const [expired, setExpired] = useState(false);
  useEffect(() => {
    let cancelled = false, timer;
    setQr(null); setExpired(false); setStatus('正在生成二维码…');
    api.qr().then(q => { if (!cancelled) { setQr(q); setStatus('使用哔哩哔哩手机端扫码'); poll(q.key); } }).catch(e => { if (!cancelled) { setStatus(e.message); setExpired(true); } });
    async function poll(key) {
      if (cancelled) return;
      try {
        const code = await api.poll(key);
        if (cancelled) return;
        if (code === 0) { const user = await api.user(); if (!cancelled) onSuccess(user); return; }
        if (code === 86038) { setStatus('二维码已过期'); setExpired(true); return; }
        setStatus(code === 86090 ? '扫码成功，请在手机上确认' : '使用哔哩哔哩手机端扫码');
      } catch (e) { if (!cancelled) setStatus(e.message); }
      if (!cancelled) timer = setTimeout(() => poll(key), 2200);
    }
    return () => { cancelled = true; clearTimeout(timer); };
  }, [refresh]);
  return <div className="login-modal"><h2>扫码登录</h2><p>哔哩哔哩账号</p><div className="qr-frame">{qr && !expired ? <img src={qr.image} alt="登录二维码"/> : expired ? <RefreshCw size={34}/> : <LoaderCircle size={30} className="spin"/>}</div><p className="qr-status">{status}</p><button className="button" onClick={() => setRefresh(n => n + 1)}><RefreshCw size={15}/>刷新二维码</button></div>;
}
function SleepModal({ player, close }) {
  const [minutes, setMinutes] = useState(30);
  return <div className="sleep-modal"><Moon size={30}/><h2>睡眠定时</h2>{player.remaining > 0 && <p>剩余 {time(player.remaining)}</p>}<div className="sleep-presets">{[10,15,30,45,60,120].map(n => <button key={n} className={`button ${minutes === n ? 'primary' : ''}`} onClick={() => setMinutes(n)}>{n === 120 ? '2 小时' : `${n} 分钟`}</button>)}</div>
    <label className="custom-minutes">自定义<input type="number" min="1" max="720" aria-label="自定义睡眠分钟" value={minutes} onChange={e => setMinutes(Number(e.target.value))}/>分钟</label>
    <button className="button primary" disabled={minutes < 1 || minutes > 720 || !Number.isFinite(minutes)} onClick={() => { player.sleep(minutes); close(); }}><Clock3 size={17}/>开始定时</button>{player.remaining > 0 && <button className="text-button" onClick={() => { player.sleep(0); close(); }}>关闭定时</button>}
  </div>;
}
createRoot(document.getElementById('root')).render(<App/>);
