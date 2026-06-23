import os
import logging
from flask import Flask, jsonify, request
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
from datetime import datetime

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database configuration from environment variables
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 5432)),
    'database': os.getenv('DB_NAME', 'microservices_db'),
    'user': os.getenv('DB_USER', 'dbuser'),
    'password': os.getenv('DB_PASSWORD', 'dbpassword123'),
}

# Connection pool for better performance
connection_pool = None

def init_connection_pool():
    global connection_pool
    try:
        connection_pool = psycopg2.pool.SimpleConnectionPool(
            1, 20,
            host=DB_CONFIG['host'],
            port=DB_CONFIG['port'],
            database=DB_CONFIG['database'],
            user=DB_CONFIG['user'],
            password=DB_CONFIG['password'],
            connect_timeout=5
        )
        logger.info("Database connection pool initialized")
    except Exception as e:
        logger.error(f"Failed to initialize connection pool: {str(e)}")
        raise

def get_db_connection():
    try:
        conn = connection_pool.getconn()
        return conn
    except Exception as e:
        logger.error(f"Failed to get database connection: {str(e)}")
        raise

def release_db_connection(conn):
    try:
        connection_pool.putconn(conn)
    except Exception as e:
        logger.error(f"Failed to release database connection: {str(e)}")

@app.before_request
def before_request():
    """Initialize connection pool on first request"""
    if not connection_pool:
        try:
            init_connection_pool()
        except Exception as e:
            logger.error(f"Connection pool initialization failed: {str(e)}")
            return jsonify({'error': 'Database unavailable'}), 503

@app.route('/health', methods=['GET'])
def health():
    """Liveness probe endpoint"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        cursor.close()
        release_db_connection(conn)
        return jsonify({'status': 'healthy'}), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503

@app.route('/ready', methods=['GET'])
def ready():
    """Readiness probe endpoint"""
    try:
        if not connection_pool:
            init_connection_pool()
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM information_schema.tables WHERE table_name=%s', ('employees',))
        result = cursor.fetchone()
        cursor.close()
        release_db_connection(conn)
        if result[0] > 0:
            return jsonify({'status': 'ready'}), 200
        else:
            return jsonify({'status': 'not_ready', 'error': 'Tables not initialized'}), 503
    except Exception as e:
        logger.error(f"Readiness check failed: {str(e)}")
        return jsonify({'status': 'not_ready', 'error': str(e)}), 503

@app.route('/api/records', methods=['GET'])
def get_records():
    """Retrieve all employee records from database"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('''
            SELECT id, name, email, department, salary, hire_date 
            FROM employees 
            ORDER BY id ASC
        ''')
        records = cursor.fetchall()
        cursor.close()
        release_db_connection(conn)
        
        return jsonify({
            'success': True,
            'count': len(records),
            'data': [dict(record) for record in records],
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Error fetching records: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/records/<int:record_id>', methods=['GET'])
def get_record(record_id):
    """Retrieve a specific employee record"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('''
            SELECT id, name, email, department, salary, hire_date 
            FROM employees 
            WHERE id = %s
        ''', (record_id,))
        record = cursor.fetchone()
        cursor.close()
        release_db_connection(conn)
        
        if not record:
            return jsonify({'success': False, 'error': 'Record not found'}), 404
        
        return jsonify({
            'success': True,
            'data': dict(record),
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Error fetching record {record_id}: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/health-info', methods=['GET'])
def health_info():
    """Extended health information"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('''
            SELECT version() as db_version, current_database(), 
            (SELECT COUNT(*) FROM employees) as employee_count
        ''')
        info = cursor.fetchone()
        cursor.close()
        release_db_connection(conn)
        
        return jsonify({
            'status': 'healthy',
            'database_version': info['db_version'],
            'current_database': info['current_database'],
            'employee_count': info['employee_count'],
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Error getting health info: {str(e)}")
        return jsonify({'status': 'error', 'error': str(e)}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal error: {str(error)}")
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    try:
        init_connection_pool()
        app.run(host='0.0.0.0', port=5000, debug=False)
    except Exception as e:
        logger.error(f"Application failed to start: {str(e)}")
        raise
