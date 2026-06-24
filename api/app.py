import os
import logging
from flask import Flask, jsonify, request
import psycopg2
from psycopg2 import pool, sql
from psycopg2.extras import RealDictCursor
from datetime import datetime, timezone

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

REQUIRED_FIELDS = {'name', 'email', 'department', 'salary', 'hire_date'}


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
        cursor.execute(
            'SELECT COUNT(*) FROM information_schema.tables WHERE table_name=%s',
            ('employees',)
        )
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
            'timestamp': datetime.now(timezone.utc).isoformat()
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
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Error fetching record {record_id}: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/records', methods=['POST'])
def create_record():
    """Create a new employee record"""
    try:
        data = request.get_json(silent=True)
        if not data:
            return jsonify({'success': False, 'error': 'Request body must be JSON'}), 400

        missing = REQUIRED_FIELDS - set(data.keys())
        if missing:
            return jsonify({
                'success': False,
                'error': f"Missing required fields: {', '.join(sorted(missing))}"
            }), 400

        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('''
            INSERT INTO employees (name, email, department, salary, hire_date)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id, name, email, department, salary, hire_date
        ''', (
            data['name'],
            data['email'],
            data['department'],
            data['salary'],
            data['hire_date'],
        ))
        new_record = cursor.fetchone()
        conn.commit()
        cursor.close()
        release_db_connection(conn)

        return jsonify({
            'success': True,
            'data': dict(new_record),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 201
    except psycopg2.errors.UniqueViolation:
        logger.warning("Duplicate email attempted")
        return jsonify({'success': False, 'error': 'Email already exists'}), 409
    except Exception as e:
        logger.error(f"Error creating record: {str(e)}")
        return jsonify({'success': False, 'error': 'An internal error occurred'}), 500


@app.route('/api/records/<int:record_id>', methods=['PUT'])
def update_record(record_id):
    """Update an existing employee record"""
    try:
        data = request.get_json(silent=True)
        if not data:
            return jsonify({'success': False, 'error': 'Request body must be JSON'}), 400

        allowed_fields = REQUIRED_FIELDS
        updates = {k: v for k, v in data.items() if k in allowed_fields}
        if not updates:
            return jsonify({
                'success': False,
                'error': f"No valid fields provided. Allowed: {', '.join(sorted(allowed_fields))}"
            }), 400

        set_assignments = sql.SQL(', ').join(
            sql.SQL('{} = %s').format(sql.Identifier(col)) for col in updates
        )
        query = sql.SQL(
            'UPDATE employees SET {} WHERE id = %s '
            'RETURNING id, name, email, department, salary, hire_date'
        ).format(set_assignments)
        values = list(updates.values()) + [record_id]

        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(query, values)
        updated = cursor.fetchone()
        conn.commit()
        cursor.close()
        release_db_connection(conn)

        if not updated:
            return jsonify({'success': False, 'error': 'Record not found'}), 404

        return jsonify({
            'success': True,
            'data': dict(updated),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 200
    except psycopg2.errors.UniqueViolation:
        logger.warning(f"Duplicate email on update for record {record_id}")
        return jsonify({'success': False, 'error': 'Email already exists'}), 409
    except Exception as e:
        logger.error(f"Error updating record {record_id}: {str(e)}")
        return jsonify({'success': False, 'error': 'An internal error occurred'}), 500


@app.route('/api/records/<int:record_id>', methods=['DELETE'])
def delete_record(record_id):
    """Delete an employee record"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('DELETE FROM employees WHERE id = %s RETURNING id', (record_id,))
        deleted = cursor.fetchone()
        conn.commit()
        cursor.close()
        release_db_connection(conn)

        if not deleted:
            return jsonify({'success': False, 'error': 'Record not found'}), 404

        return jsonify({
            'success': True,
            'message': f'Record {record_id} deleted successfully',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Error deleting record {record_id}: {str(e)}")
        return jsonify({'success': False, 'error': 'An internal error occurred'}), 500


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
            'timestamp': datetime.now(timezone.utc).isoformat()
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
