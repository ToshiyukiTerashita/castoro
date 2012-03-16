/*
 *   Copyright 2010 Ricoh Company, Ltd.
 *
 *   This file is part of Castoro.
 *
 *   Castoro is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Lesser General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   Castoro is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Lesser General Public License for more details.
 *
 *   You should have received a copy of the GNU Lesser General Public License
 *   along with Castoro.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "cache.hxx"
#include "memory.hxx"

Cache::Cache()
{
  _db = (kc::PolyDB*)ruby_xmalloc(sizeof(kc::PolyDB));
  new( (void*)_db ) kc::PolyDB;
  _expire = 15;
  _peerSize = 3;
  _logger = NULL;
  _locker = NULL;
  _requests = 0;
  _hits = 0;
}

Cache::~Cache()
{
  if (_db) {
    _db->close();
    _db->~PolyDB();
    ruby_xfree(_db);
    _db = NULL;
  }
}

void
Cache::init(VALUE size, VALUE options)
{
  if (RTEST(rb_funcall(size, id_less_eql, 1, INT2NUM(0)))) {
    rb_throw("size must be > 0", rb_eArgError);
  }

  VALUE logger = rb_hash_aref(options, sym_logger);
  if (RTEST(logger)) _logger = logger;

  VALUE expire = rb_hash_aref(options, sym_watchdog_limit);
  if (RTEST(expire)) {
    if (RTEST(rb_funcall(expire, id_less_eql, 1, INT2NUM(0)))) {
      rb_throw("watchdog_limit must be > 0", rb_eArgError);
    }
    _expire = NUM2UINT(expire);
  }
  VALUE peerSize = rb_hash_aref(options, sym_peer_size);
  if (RTEST(peerSize)) {
    if (RTEST(rb_funcall(peerSize, id_less_eql, 1, INT2NUM(0)))) {
      rb_throw("peer_size must be > 0", rb_eArgError);
    }
    _peerSize = NUM2UINT(peerSize);
  }
  _valsiz = Val::getSize(_peerSize);

  VALUE format = rb_str_new2("*#capsiz=%d");
  VALUE arg = rb_funcall(format, id_format, 1, size);

  _locker = rb_class_new_instance(0, NULL, cls_mutex);
  if (!_db->open(StringValuePtr(arg))) raiseOnError();

  _peers.init();
}

void
Cache::mark()
{
  _peers.mark();
  if (_logger) rb_gc_mark(_logger);
  if (_locker) rb_gc_mark(_locker);
}

VALUE
Cache::find(VALUE _c, VALUE _t, VALUE _r)
{
  VALUE result = rb_ary_new();
  bool hit = false;

  _requests++;

  Key k(NUM2ULL(_c), NUM2UINT(_t));
  Val v(_peerSize);

  if (!get(k, &v, true)) return result;

  if (NUM2UINT(_r) != v.getRev()) return result;

  PeerId* p = v.getPeers();
  for (uint8_t i = 0; i < _peerSize; i++) {
    if (*(p+i) != 0 && _peers.getStatus(*(p+i)).isReadable(_expire)) {
      hit = true;
      rb_ary_push(result, rb_funcall(ID2SYM(*(p+i)), id_to_s, 0));
    }
  }

  if (hit) _hits++;
  return result;
}

VALUE
Cache::findPeers()
{
  VALUE ret = rb_ary_new();
  Memory<ID> peers(_peers.getCount());
  uint64_t count;

  _peers.find(peers.pointer(), &count);
  for (uint64_t i = 0; i < count; i++) {
    rb_ary_push(ret, rb_funcall(ID2SYM(*(peers.pointer()+i)), id_to_s, 0));
  }
  return ret;
}

VALUE
Cache::findPeers(VALUE requireSpaces)
{
  VALUE ret = rb_ary_new();
  Memory<ID> peers(_peers.getCount());
  uint64_t count;

  _peers.find(peers.pointer(), &count, _expire, NUM2ULL(requireSpaces));
  for (uint64_t i = 0; i < count; i++) {
    rb_ary_push(ret, rb_funcall(ID2SYM(*(peers.pointer()+i)), id_to_s, 0));
  }
  return ret;
}

void
Cache::insertElement(VALUE _p, VALUE _c, VALUE _t, VALUE _r)
{
  uint8_t r = (uint8_t)(NUM2UINT(_r) & 255);
  Key k(NUM2ULL(_c), NUM2UINT(_t));
  Val v(_peerSize);
  PeerId p = rb_to_id(_p);
  Memory<char> m(_valsiz);
  bool ret;

  rb_mutex_lock(_locker);
  get(k, &v, false);
  v.setRev(r);
  v.insertPeer(p);
  v.serialize(m.pointer());
  ret = _db->set((const char*)&k, sizeof(k), m.pointer(), _valsiz);
  rb_mutex_unlock(_locker);

  if (!ret) raiseOnError();
}

void
Cache::eraseElement(VALUE _p, VALUE _c, VALUE _t, VALUE _r)
{
  char r = (char)(NUM2UINT(_r) & 255);
  Key k(NUM2ULL(_c), NUM2UINT(_t));
  Val v(_peerSize);
  PeerId p = rb_to_id(_p);
  Memory<char> m(_valsiz);
  bool ret = true;

  rb_mutex_lock(_locker);
  if (get(k, &v, false) && r == v.getRev()) {
    v.removePeer(p);
    if (v.isEmpty()) {
      ret = _db->remove((const char*)&k, sizeof(k));
    } else {
      v.serialize(m.pointer());
      ret = _db->set((const char*)&k, sizeof(k), m.pointer(), _valsiz);
    }
  }
  rb_mutex_unlock(_locker);

  if (!ret) raiseOnError();
}

VALUE
Cache::getPeerStatus(VALUE _p)
{
  VALUE ret = rb_hash_new();
  Status st = _peers.getStatus(rb_to_id(_p));
  rb_hash_aset(ret, sym_status, ULL2NUM(st.getStatus()));
  rb_hash_aset(ret, sym_available, UINT2NUM(st.getAvailable()));
  return ret;
}

void
Cache::setPeerStatus(VALUE _p, VALUE _s)
{
  VALUE a = rb_hash_aref(_s, sym_available);
  VALUE s = rb_hash_aref(_s, sym_status);

  if (RTEST(a) && RTEST(s)) {
    _peers.set(rb_to_id(_p), (uint64_t)NUM2ULL(a), (uint32_t)NUM2UINT(s));
  } else if (RTEST(a)) {
    _peers.set(rb_to_id(_p), (uint64_t)NUM2ULL(a));
  } else if (RTEST(s)) {
    _peers.set(rb_to_id(_p), (uint32_t)NUM2UINT(s));
  }
}

void
Cache::dump(VALUE _f)
{
  Traverser tr(_db, _locker, _peerSize, _valsiz);

  tr.traverse(Dumper(_f));
  raiseOnError();
  rb_funcall(_f, id_puts, 0);
}

void
Cache::dump(VALUE _f, VALUE _p)
{
  Traverser tr(_db, _locker, _peerSize, _valsiz);

  tr.traverse(FilteredDumper(_f, _p));
  raiseOnError();
  rb_funcall(_f, id_puts, 0);
}

VALUE
Cache::stat(VALUE _k)
{
  uint64_t ret = 0;

  if (rb_funcall(_k, id_equal, 1, stat_cache_expire)) {
    ret = _expire;

  } else if (rb_funcall(_k, id_equal, 1, stat_cache_requests)) {
    ret = _requests;

  } else if (rb_funcall(_k, id_equal, 1, stat_cache_hits)) {
    ret = _hits;

  } else if (rb_funcall(_k, id_equal, 1, stat_cache_count_clear)) {
    ret = (_requests > 0) ? ((_hits * 1000) / _requests) : 0;
    _requests = _hits = 0;

  } else if (rb_funcall(_k, id_equal, 1, stat_allocate_pages)) {
    ret = 0; // In kc-based cache there is no concept of a page segment.

  } else if (rb_funcall(_k, id_equal, 1, stat_free_pages)) {
    ret = 0; // In kc-based cache there is no concept of a page segment.

  } else if (rb_funcall(_k, id_equal, 1, stat_active_pages)) {
    ret = 0; // In kc-based cache there is no concept of a page segment.

  } else if (rb_funcall(_k, id_equal, 1, stat_have_status_peers)) {
    ret = _peers.getCount();

  } else if (rb_funcall(_k, id_equal, 1, stat_active_peers)) {
    ret = _peers.getWritableCount(_expire);

  } else if (rb_funcall(_k, id_equal, 1, stat_readable_peers)) {
    ret = _peers.getReadableCount(_expire);

  }
      
  return ULL2NUM(ret);
}

void
Cache::raiseOnError() const
{
  kc::PolyDB::Error err = _db->error();
  uint32_t code = err.code();
  const char* message = err.message();
  VALUE klass;

  switch(code) {
  case kc::PolyDB::Error::NOIMPL:
    klass = cls_err_noimpl;
    break;
  case kc::PolyDB::Error::INVALID:
    klass = cls_err_invalid;
    break;
  case kc::PolyDB::Error::NOREPOS:
    klass = cls_err_norepos;
    break;
  case kc::PolyDB::Error::NOPERM:
    klass = cls_err_noperm;
    break;
  case kc::PolyDB::Error::BROKEN:
    klass = cls_err_broken;
    break;
  case kc::PolyDB::Error::SYSTEM:
    klass = cls_err_system;
    break;
  case kc::PolyDB::Error::MISC:
    klass = cls_err_misc;
    break;
  default:
    return;
  }
  if (rb_mutex_locked_p(_locker)) rb_mutex_unlock(_locker);
  rb_raise(klass, "%u: %s", code, message);
}

bool
Cache::get(const Key& k, Val* v, bool lock) const
{
  bool ret;
  Memory<char> m(_valsiz);

  if (lock) rb_mutex_lock(_locker);
  ret = _db->get((const char*)&k, sizeof(k), m.pointer(), _valsiz) != -1;
  if (lock) rb_mutex_unlock(_locker);

  if (ret) {
    v->deserialize(m.pointer());
  } else {
    raiseOnError();
  } 

  return ret;
}

