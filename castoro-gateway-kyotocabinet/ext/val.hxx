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

#ifndef _INCLUDE_RECORD_H_
#define _INCLUDE_RECORD_H_

#include "stdinc.hxx"

class Val
{
  public:
    static size_t getSize(uint8_t peerSize);

    Val(uint8_t peerSize);

    void clear();
    uint8_t getRev() const;
    void setRev(uint8_t rev);
    bool isInclude(PeerId peer) const;
    bool isFull() const;
    bool isEmpty() const;
    void insertPeer(PeerId peer);
    void removePeer(PeerId peer);
    PeerId* getPeers() const;
    uint8_t getPeerSize() const;

    void serialize(void* stream) const;
    void deserialize(const void* stream);

  private:
    uint8_t _rev;
    uint8_t _peerSize;
    PeerId* _peers;
};

#endif // _INCLUDE_RECORD_H_

