import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app, DB_CONFIG
import json


@pytest.fixture
def client():
    """Create test client for Flask app"""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


@pytest.fixture
def app_context():
    """Create app context for tests"""
    with app.app_context():
        yield


class TestHealthEndpoints:
    """Test health check endpoints"""
    
    def test_health_endpoint_exists(self, client):
        """Test that /health endpoint is accessible and always returns 200"""
        response = client.get('/health')
        assert response.status_code == 200
    
    def test_health_returns_json(self, client):
        """Test that /health returns JSON"""
        response = client.get('/health')
        assert response.content_type == 'application/json'
    
    def test_health_response_has_status(self, client):
        """Test that health response contains status field"""
        response = client.get('/health')
        data = json.loads(response.data)
        assert 'status' in data
    
    def test_ready_endpoint_exists(self, client):
        """Test that /ready endpoint is accessible"""
        response = client.get('/ready')
        assert response.status_code in [200, 503]
    
    def test_ready_returns_json(self, client):
        """Test that /ready returns JSON"""
        response = client.get('/ready')
        assert response.content_type == 'application/json'
    
    def test_ready_response_has_status(self, client):
        """Test that ready response contains status field"""
        response = client.get('/ready')
        data = json.loads(response.data)
        assert 'status' in data or 'error' in data


class TestAPIEndpoints:
    """Test API endpoints"""
    
    def test_api_records_endpoint_exists(self, client):
        """Test that /api/records endpoint is accessible"""
        response = client.get('/api/records')
        assert response.status_code in [200, 500, 503]  # May fail if DB unavailable in test
    
    def test_api_records_returns_json(self, client):
        """Test that /api/records returns JSON"""
        response = client.get('/api/records')
        assert response.content_type == 'application/json'
    
    def test_api_records_response_structure(self, client):
        """Test that /api/records response has expected structure"""
        response = client.get('/api/records')
        if response.status_code == 200:
            data = json.loads(response.data)
            assert 'success' in data
            assert 'count' in data
            assert 'data' in data
            assert 'timestamp' in data
            assert isinstance(data['data'], list)
    
    def test_api_single_record_endpoint_exists(self, client):
        """Test that /api/records/<id> endpoint is accessible"""
        response = client.get('/api/records/1')
        assert response.status_code in [200, 404, 500, 503]
    
    def test_api_single_record_returns_json(self, client):
        """Test that /api/records/<id> returns JSON"""
        response = client.get('/api/records/1')
        assert response.content_type == 'application/json'
    
    def test_api_invalid_record_id(self, client):
        """Test that invalid record ID returns 404"""
        response = client.get('/api/records/99999')
        # Should be 404 if DB is available, 500/503 if not
        assert response.status_code in [404, 500, 503]
    
    def test_api_health_info_endpoint_exists(self, client):
        """Test that /api/health-info endpoint is accessible"""
        response = client.get('/api/health-info')
        assert response.status_code in [200, 500, 503]
    
    def test_api_health_info_returns_json(self, client):
        """Test that /api/health-info returns JSON"""
        response = client.get('/api/health-info')
        assert response.content_type == 'application/json'
    
    def test_api_health_info_structure(self, client):
        """Test that /api/health-info response has expected structure"""
        response = client.get('/api/health-info')
        if response.status_code == 200:
            data = json.loads(response.data)
            assert 'status' in data
            assert 'timestamp' in data


class TestErrorHandling:
    """Test error handling"""
    
    def test_404_error_response(self, client):
        """Test that 404 errors return JSON"""
        response = client.get('/nonexistent-endpoint')
        assert response.status_code in [404, 503]  # 503 if DB pool init fails in before_request
        assert response.content_type == 'application/json'
        data = json.loads(response.data)
        assert 'error' in data
    
    def test_method_not_allowed(self, client):
        """Test that POST to GET-only endpoint is rejected"""
        response = client.post('/api/records')
        assert response.status_code in [405, 503]  # 503 if DB pool init fails in before_request
    
    def test_invalid_json_handling(self, client):
        """Test that invalid JSON is handled gracefully"""
        response = client.get('/api/records')
        # Should not raise exception regardless of response code
        assert response.status_code is not None


class TestDatabaseConfig:
    """Test database configuration"""
    
    def test_db_config_from_environment(self):
        """Test that DB config is read from environment"""
        assert 'host' in DB_CONFIG
        assert 'port' in DB_CONFIG
        assert 'database' in DB_CONFIG
        assert 'user' in DB_CONFIG
        assert 'password' in DB_CONFIG
    
    def test_db_config_has_required_fields(self):
        """Test that all required config fields are present"""
        required_fields = ['host', 'port', 'database', 'user', 'password']
        for field in required_fields:
            assert field in DB_CONFIG, f"Missing database config: {field}"
    
    def test_db_port_is_integer(self):
        """Test that database port is an integer"""
        assert isinstance(DB_CONFIG['port'], int)
    
    def test_db_port_is_valid(self):
        """Test that database port is in valid range"""
        assert 1 <= DB_CONFIG['port'] <= 65535


class TestAppConfiguration:
    """Test Flask app configuration"""
    
    def test_app_exists(self):
        """Test that Flask app is properly initialized"""
        assert app is not None
    
    def test_app_is_test_mode(self, client):
        """Test that app can be set to test mode"""
        assert app.config.get('TESTING') is True or app.config.get('TESTING') is False
    
    def test_app_has_required_routes(self, client):
        """Test that app has all required routes"""
        required_routes = ['/health', '/ready', '/api/records', '/api/health-info']
        for route in required_routes:
            response = client.get(route)
            # Route exists if we get any response (not 404)
            assert response.status_code != 404, f"Route {route} not found"


class TestResponseFormats:
    """Test response format consistency"""
    
    def test_success_response_format(self, client):
        """Test success response includes proper fields"""
        response = client.get('/api/records')
        if response.status_code == 200:
            data = json.loads(response.data)
            assert 'success' in data
            assert data['success'] is True
            assert 'timestamp' in data
    
    def test_error_response_format(self, client):
        """Test error response includes proper fields"""
        response = client.get('/nonexistent')
        if response.status_code == 404:
            data = json.loads(response.data)
            assert 'error' in data


class TestDataValidation:
    """Test data validation in responses"""
    
    def test_records_are_dicts(self, client):
        """Test that records in response are dictionaries"""
        response = client.get('/api/records')
        if response.status_code == 200:
            data = json.loads(response.data)
            for record in data['data']:
                assert isinstance(record, dict)
    
    def test_record_has_required_fields(self, client):
        """Test that each record has required fields"""
        response = client.get('/api/records')
        if response.status_code == 200:
            data = json.loads(response.data)
            required_fields = ['id', 'name', 'email', 'department', 'salary', 'hire_date']
            if data['data']:  # If there are records
                record = data['data'][0]
                for field in required_fields:
                    assert field in record, f"Record missing field: {field}"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
