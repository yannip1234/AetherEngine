import http.client
from pathlib import Path
import tempfile
import threading
import unittest

from native_subtitle_fixtures import FIXTURES, byte_range, check_test_result, origin


class OwnedOriginTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        (self.directory / FIXTURES[0]).write_bytes(b'0123456789')
        self.server = origin(self.directory)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def request(self, method='GET', path='/' + FIXTURES[0], range_header=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        try:
            connection.request(method, path, headers={'Range': range_header} if range_header else {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_full_get_and_head(self):
        status, headers, body = self.request()
        self.assertEqual((status, body, headers['Content-Length']), (200, b'0123456789', '10'))
        status, headers, body = self.request('HEAD')
        self.assertEqual((status, body, headers['Content-Length']), (200, b'', '10'))

    def test_ranges_and_head(self):
        for header, expected, content_range in [
            ('bytes=2-4', b'234', 'bytes 2-4/10'),
            ('bytes=-3', b'789', 'bytes 7-9/10'),
            ('bytes=8-', b'89', 'bytes 8-9/10'),
            ('bytes=8-100', b'89', 'bytes 8-9/10'),
            ('bytes=-100', b'0123456789', 'bytes 0-9/10'),
        ]:
            with self.subTest(header=header):
                status, headers, body = self.request(range_header=header)
                self.assertEqual((status, body, headers['Content-Range']), (206, expected, content_range))
                status, headers, body = self.request('HEAD', range_header=header)
                self.assertEqual((status, body, headers['Content-Length']), (206, b'', str(len(expected))))

    def test_invalid_ranges(self):
        for header in ['bytes=10-', 'bytes=8-2', 'bytes=-0', 'bytes=1-2,4-6', 'bytes=-', 'other=0-2']:
            with self.subTest(header=header):
                status, headers, body = self.request(range_header=header)
                self.assertEqual((status, body, headers['Content-Range']), (416, b'', 'bytes */10'))
                with self.assertRaises(ValueError):
                    byte_range(header, 10)

    def test_only_allowlisted_existing_fixtures(self):
        for path in ['/../secret', '/%2e%2e/secret', '/control/arm/key', '/' + FIXTURES[1]]:
            with self.subTest(path=path):
                self.assertEqual(self.request(path=path)[0], 404)


class TestResultChecks(unittest.TestCase):
    def test_requires_six_without_failures_or_skips(self):
        check_test_result('Executed 6 tests, with 0 failures (0 unexpected) in 20 seconds')
        for output in [
            'Executed 6 tests, with 6 tests skipped and 0 failures (0 unexpected)',
            'Executed 6 tests, with 1 failure (0 unexpected)',
            'Executed 5 tests, with 0 failures (0 unexpected)',
            'Test run with 0 tests passed',
        ]:
            with self.subTest(output=output), self.assertRaises(AssertionError):
                check_test_result(output)


if __name__ == '__main__':
    unittest.main()
