# Copyright (c) 2012, Adobe Systems Incorporated
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# * Neither the name of Adobe Systems Incorporated nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'digest'
require 'zlib'
require 'tempfile'
require 'fileutils'

supportsLZMA = false

class StringFile
	def initialize data
		@data = data
	end

	def read num=-1
		num = @data.length if num < 0
		res = @data[0,num]
		@data = @data[num, @data.length]
		res
	end

	def close
		@data = nil
	end

	def flush
	end
end

def consumeSwfTag f
	tagBytes = ''
	recordHeaderRaw = f.read 2
	tagBytes += recordHeaderRaw

	throw 'Bad SWF: Unexpected end of file' if recordHeaderRaw == ''

	recordHeader = recordHeaderRaw.unpack('CC')
	tagCode = ((recordHeader[1] & 0xff) << 8) | (recordHeader[0] & 0xff)
    tagType = (tagCode >> 6)
    tagLength = tagCode & 0x3f
    if tagLength == 0x3f
        ll = f.read(4)
        longlength = ll.unpack "CCCC"
        tagLength = ((longlength[3]&0xff) << 24) | ((longlength[2]&0xff) << 16) | ((longlength[1]&0xff) << 8) | (longlength[0]&0xff)
        tagBytes += ll
    end
    tagBytes += f.read(tagLength)
    return tagType, tagBytes
end

def outputTelemetryTag o, passwordClear
	lengthBytes = 2 # reserve
    if passwordClear
        sha = Digest::SHA2.new
        sha << passwordClear
        passwordDigest = sha.digest
        lengthBytes += passwordDigest.length
    end

    # Record header
    code = 93
    if lengthBytes >= 63
        o << [code << 6 | 0x3f, lengthBytes].pack('vV')
    else
        o << [code << 6 | lengthBytes].pack('v')
    end

    # Reserve
    o << [0].pack('v')
    
    # Password
    o << passwordDigest if passwordClear
end



if ARGV.count < 1
	puts "Usage: ruby #{__FILE__} SWF_FILE [PASSWORD]"
	puts "If PASSWORD is provided, then a password will be required to view advanced telemetry in Monocle."
	exit false
end

infile = ARGV[0]
passwordClear ||= ARGV[1]

swfFH = File.open infile, 'rb'
signature = swfFH.read 3
swfVersion = swfFH.read 1
ln = swfFH.read(4).unpack('V')[0]

if signature == 'CWS'
	decompressedFH = StringFile.new(Zlib::Inflate.inflate(swfFH.read))
	swfFH.close
	swfFH = decompressedFH
elsif signature == 'ZWS'
	throw 'LZMA decompression not yet supported' unless supportsLZMA
elsif signature == 'FWS'
	;
else
	throw "Bad SWF: Unrecognized signature: #{signature}"
end
	
f = swfFH
	
o = Tempfile.new('swf', mode: (File::RDWR | File::BINARY | File::CREAT))
o << signature << swfVersion << [0].pack('L') # FileLength - we'll fix this up later

rs = f.read 1
r = rs.unpack 'C'
rbits = (r[0] & 0xff) >> 3
rrbytes = (7 + (rbits*4) - 3) / 8;
o << rs << f.read(rrbytes.to_i)

o << f.read(4) # FrameRate and FrameCount

while true
	tagType, tagBytes = consumeSwfTag(f)
	if tagType == 93
        throw "Bad SWF: already has EnableTelemetry tag"
    elsif tagType == 92
        throw "Bad SWF: Signed SWFs are not supported"
    elsif tagType == 69
    	o << tagBytes

    	nextTagType, nextTagBytes = consumeSwfTag(f)
    	writeAfterNextTag = nextTagType == 77
    	o << nextTagBytes if writeAfterNextTag

    	outputTelemetryTag o, passwordClear

    	o << nextTagBytes unless writeAfterNextTag

    	tagType, tagBytes = consumeSwfTag(f)
    end

    o << tagBytes

    break if tagType == 0
end

uncompressedLength = o.tell
o.seek 4
o << [uncompressedLength].pack("L")
o.flush
o.seek 0

outFile = File.open(infile, 'wb')

if signature == 'FWS'
	FileUtils.copy_stream o, outFile
else
	outFile << o.read(8)
	if signature == 'CWS'
		outFile << Zlib::Deflate.deflate(o.read)
	elsif signature == 'ZWS'
		# not supported yet
	end
end

outFile.close

if passwordClear
	puts "Added opt-in flag with encrypted password #{passwordClear}"
else
	puts "Added opt-in flag with no password"
end




