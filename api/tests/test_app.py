import json
import unittest
from unittest.mock import patch, MagicMock
import sys
import os

# Ensure the api directory is on the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import app as flask_app


class TestHealthEndpoints(unittest.TestCase):
    def setUp(self):
        flask_app.app.config['TESTING'] = True
        self.client = flask_app.app.test_client()

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_health_ok(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/health')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertEqual(data['status'], 'healthy')

    @patch('app.get_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_health_db_error(self, mock_get_conn):
        mock_get_conn.side_effect = Exception('DB down')

        resp = self.client.get('/health')
        self.assertEqual(resp.status_code, 503)
        data = json.loads(resp.data)
        self.assertEqual(data['status'], 'unhealthy')

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_ready_ok(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = (1,)
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/ready')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertEqual(data['status'], 'ready')

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_ready_tables_missing(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = (0,)
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/ready')
        self.assertEqual(resp.status_code, 503)


class TestGetRecordsEndpoints(unittest.TestCase):
    def setUp(self):
        flask_app.app.config['TESTING'] = True
        self.client = flask_app.app.test_client()

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_get_all_records(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchall.return_value = [
            {'id': 1, 'name': 'Alice', 'email': 'alice@example.com',
             'department': 'Engineering', 'salary': 95000, 'hire_date': '2020-01-15'},
        ]
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/api/records')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data['success'])
        self.assertEqual(data['count'], 1)
        self.assertEqual(len(data['data']), 1)

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_get_single_record_found(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 1, 'name': 'Alice', 'email': 'alice@example.com',
            'department': 'Engineering', 'salary': 95000, 'hire_date': '2020-01-15'
        }
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/api/records/1')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data['success'])

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_get_single_record_not_found(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/api/records/999')
        self.assertEqual(resp.status_code, 404)
        data = json.loads(resp.data)
        self.assertFalse(data['success'])


class TestCreateRecordEndpoint(unittest.TestCase):
    def setUp(self):
        flask_app.app.config['TESTING'] = True
        self.client = flask_app.app.test_client()

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_create_record_success(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 9, 'name': 'Ivan', 'email': 'ivan@example.com',
            'department': 'QA', 'salary': 80000, 'hire_date': '2023-01-01'
        }
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        payload = {
            'name': 'Ivan',
            'email': 'ivan@example.com',
            'department': 'QA',
            'salary': 80000,
            'hire_date': '2023-01-01'
        }
        resp = self.client.post(
            '/api/records',
            data=json.dumps(payload),
            content_type='application/json'
        )
        self.assertEqual(resp.status_code, 201)
        data = json.loads(resp.data)
        self.assertTrue(data['success'])

    @patch('app.connection_pool', new=MagicMock())
    def test_create_record_missing_fields(self):
        payload = {'name': 'Ivan'}
        resp = self.client.post(
            '/api/records',
            data=json.dumps(payload),
            content_type='application/json'
        )
        self.assertEqual(resp.status_code, 400)
        data = json.loads(resp.data)
        self.assertFalse(data['success'])
        self.assertIn('Missing required fields', data['error'])

    @patch('app.connection_pool', new=MagicMock())
    def test_create_record_no_body(self):
        resp = self.client.post('/api/records', data='', content_type='application/json')
        self.assertEqual(resp.status_code, 400)


class TestUpdateRecordEndpoint(unittest.TestCase):
    def setUp(self):
        flask_app.app.config['TESTING'] = True
        self.client = flask_app.app.test_client()

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_update_record_success(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 1, 'name': 'Alice Updated', 'email': 'alice@example.com',
            'department': 'Engineering', 'salary': 100000, 'hire_date': '2020-01-15'
        }
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        payload = {'salary': 100000, 'name': 'Alice Updated'}
        resp = self.client.put(
            '/api/records/1',
            data=json.dumps(payload),
            content_type='application/json'
        )
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data['success'])

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_update_record_not_found(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.put(
            '/api/records/999',
            data=json.dumps({'name': 'Ghost'}),
            content_type='application/json'
        )
        self.assertEqual(resp.status_code, 404)

    @patch('app.connection_pool', new=MagicMock())
    def test_update_record_no_valid_fields(self):
        payload = {'unknown_field': 'value'}
        resp = self.client.put(
            '/api/records/1',
            data=json.dumps(payload),
            content_type='application/json'
        )
        self.assertEqual(resp.status_code, 400)

    @patch('app.connection_pool', new=MagicMock())
    def test_update_record_no_body(self):
        resp = self.client.put('/api/records/1', data='', content_type='application/json')
        self.assertEqual(resp.status_code, 400)


class TestDeleteRecordEndpoint(unittest.TestCase):
    def setUp(self):
        flask_app.app.config['TESTING'] = True
        self.client = flask_app.app.test_client()

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_delete_record_success(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = (1,)
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.delete('/api/records/1')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data['success'])

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_delete_record_not_found(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.delete('/api/records/999')
        self.assertEqual(resp.status_code, 404)
        data = json.loads(resp.data)
        self.assertFalse(data['success'])


class TestHealthInfoEndpoint(unittest.TestCase):
    def setUp(self):
        flask_app.app.config['TESTING'] = True
        self.client = flask_app.app.test_client()

    @patch('app.get_db_connection')
    @patch('app.release_db_connection')
    @patch('app.connection_pool', new=MagicMock())
    def test_health_info_ok(self, mock_release, mock_get_conn):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'db_version': 'PostgreSQL 15.0',
            'current_database': 'microservices_db',
            'employee_count': 8
        }
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        resp = self.client.get('/api/health-info')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertEqual(data['status'], 'healthy')
        self.assertEqual(data['employee_count'], 8)


if __name__ == '__main__':
    unittest.main()
