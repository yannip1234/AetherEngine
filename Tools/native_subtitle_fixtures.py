#!/usr/bin/env python3
"""Generate owned MKVs and run the six native subtitle tests on macOS."""
import argparse
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
from urllib.parse import urlsplit

FIXTURES = ('owned-seek-tracks.mkv', 'owned-forced-sdh.mkv', 'owned.mkv')


def byte_range(header, size):
    # Single-range behavior shared with Signal's owned diagnostic origin.
    if header is None:
        return 0, size - 1, False
    match = re.fullmatch(r'bytes=(\d*)-(\d*)', header)
    if not match or not any(match.groups()):
        raise ValueError('Unsupported range')
    first, last = match.groups()
    if not first:
        count = int(last)
        if count <= 0:
            raise ValueError('Empty suffix')
        return max(0, size - count), size - 1, True
    start, end = int(first), min(int(last), size - 1) if last else size - 1
    if start >= size or end < start:
        raise ValueError('Unsatisfiable range')
    return start, end, True


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def __init__(self, *args, directory, **kwargs):
        self.directory = directory
        super().__init__(*args, **kwargs)

    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.serve(False)

    def do_GET(self):
        self.serve(True)

    def serve(self, body):
        name = urlsplit(self.path).path
        if name not in ['/' + item for item in FIXTURES]:
            self.send_error(404)
            return
        path = self.directory / name[1:]
        try:
            stream = path.open('rb')
        except OSError:
            self.send_error(404)
            return
        with stream:
            size = os.fstat(stream.fileno()).st_size
            try:
                start, end, partial_range = byte_range(self.headers.get('Range'), size)
            except ValueError:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            self.send_response(206 if partial_range else 200)
            self.send_header('Content-Type', 'video/x-matroska')
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            self.send_header('Cache-Control', 'no-store')
            if partial_range:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.end_headers()
            if not body:
                return
            try:
                stream.seek(start)
                remaining = end - start + 1
                while remaining:
                    chunk = stream.read(min(remaining, 65536))
                    if not chunk:
                        raise OSError('Fixture changed during request')
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass


def origin(directory):
    return ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=directory))


def ffmpeg(directory, arguments):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
                    *arguments], cwd=directory, check=True, timeout=120)


def generate(directory):
    subtitle = directory / 'english.srt'
    subtitle.write_text('1\n00:00:00,000 --> 00:00:10,000\nOwned English caption one\n\n'
                        '2\n00:00:10,000 --> 00:00:20,000\nOwned English caption two\n\n'
                        '3\n00:00:20,000 --> 00:00:30,000\nOwned English caption three\n')
    ffmpeg(directory, [
        '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24:duration=30',
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=30',
        '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000:duration=30',
        '-i', 'english.srt', '-map', '0:v', '-map', '1:a', '-map', '2:a', '-map', '3:s',
        '-t', '30', '-c:v', 'libx264', '-preset', 'ultrafast', '-threads', '2',
        '-profile:v', 'baseline', '-pix_fmt', 'yuv420p', '-g', '48', '-sc_threshold', '0',
        '-c:a', 'aac', '-b:a', '64k', '-ac', '1', '-c:s', 'srt',
        '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=spa',
        '-metadata:s:s:0', 'language=eng', '-metadata:s:s:0', 'title=English',
        '-disposition:a:0', 'default', '-disposition:a:1', '0',
        '-disposition:s:0', '0', FIXTURES[0]])
    ffmpeg(directory, ['-i', FIXTURES[0], '-map', '0', '-c', 'copy',
                       '-disposition:s:0', 'forced+hearing_impaired', FIXTURES[1]])
    ffmpeg(directory, ['-i', FIXTURES[0], '-map', '0:v', '-map', '0:a',
                       '-c', 'copy', FIXTURES[2]])
    for name in FIXTURES:
        validate(directory / name)


def validate(path):
    probe = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)
    ], text=True, timeout=20))
    assert 29.9 <= float(probe['format']['duration']) <= 30.2, path
    streams = probe['streams']
    assert [s['codec_name'] for s in streams if s['codec_type'] == 'video'] == ['h264']
    audio = [s for s in streams if s['codec_type'] == 'audio']
    assert [s['codec_name'] for s in audio] == ['aac', 'aac']
    assert [s['tags']['language'] for s in audio] == ['eng', 'spa']
    assert [s['disposition']['default'] for s in audio] == [1, 0]
    subtitles = [s for s in streams if s['codec_type'] == 'subtitle']
    if path.name == 'owned.mkv':
        assert not subtitles
    else:
        assert len(subtitles) == 1 and subtitles[0]['codec_name'] == 'subrip'
        assert subtitles[0]['tags']['language'] == 'eng'
        disposition = subtitles[0]['disposition']
        expected = int(path.name == 'owned-forced-sdh.mkv')
        assert disposition['forced'] == disposition['hearing_impaired'] == expected
        assert disposition['default'] == 0


def check_test_result(output):
    # Check XCTest's class summary; Swift Testing also prints its own zero-test summary.
    matches = re.findall(r'Executed 6 tests, (?:with (\d+) tests? skipped and )?with 0 failures', output)
    assert matches and all(not count or int(count) == 0 for count in matches), \
        'Expected six native XCTest cases with zero failures and zero skips'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only', action='store_true', help='Generate/probe fixtures and check HTTP; no Swift build')
    args = parser.parse_args()
    for executable in ('ffmpeg', 'ffprobe'):
        if not shutil.which(executable):
            parser.error(f'Required executable not found: {executable}')
    package = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='aether-owned-subtitles-') as temporary:
        directory = Path(temporary)
        generate(directory)
        server = origin(directory)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        address = f'http://127.0.0.1:{server.server_port}'
        try:
            from urllib.request import Request, urlopen
            for name in FIXTURES:
                with urlopen(Request(f'{address}/{name}', headers={'Range': 'bytes=0-31'}), timeout=5) as response:
                    assert response.status == 206 and len(response.read()) == 32
            print('Validated three owned 30-second MKVs and loopback byte ranges.', flush=True)
            if not args.check_only:
                environment = dict(os.environ, SIGNAL_CONTAINER_TRACK_ORIGIN=address)
                result = subprocess.run(['swift', 'test', '--filter', 'NativeSubtitleAutomaticSelectionTests'],
                                        cwd=package, env=environment, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=1800)
                print(result.stdout)
                result.check_returncode()
                check_test_result(result.stdout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    main()
