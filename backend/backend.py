from flask import Flask, request, jsonify
import psycopg2
from psycopg2 import sql
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
from datetime import datetime, timedelta
from functools import wraps
import socket
import json
import threading
# Загрузка переменных окружения
load_dotenv()

app = Flask(__name__)
app.config['SECRET_KEY'] = "12345"
# Функция для подключения к PostgreSQL

class ChargingStationManager:
    _instance = None
    connections = {}  # Хранит соединения с станциями: {station_id: socket}
    command_sockets = {}  # Хранит командные соединения с станциями
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ChargingStationManager, cls).__new__(cls)
            cls._instance.init()
        return cls._instance
    
    def init(self):
        # Здесь можно добавить инициализацию, если нужно
        pass
    
    def add_connection(self, station_id, socket):
        self.connections[station_id] = socket
    
    def add_command_connection(self, station_id, socket):
        self.command_sockets[station_id] = socket
    
    def remove_connection(self, station_id):
        self.connections.pop(station_id, None)
        self.command_sockets.pop(station_id, None)
    
    def send_command(self, station_id, command):
        """Отправляет команду на станцию через отдельное соединение"""
        try:
            if station_id in self.command_sockets:
                sock = self.command_sockets[station_id]
                sock.sendall(json.dumps(command).encode('utf-8'))
                return True
            return False
        except Exception as e:
            print(f"Error sending command to station {station_id}: {e}")
            self.command_sockets.pop(station_id, None)
            return False
        

station_manager = ChargingStationManager()        


def get_db_connection():
    conn = psycopg2.connect(
        host='localhost',
        database='postgres',
        user='postgres',
        password='postgres',
        port='5432'
    )
    return conn

# Инициализация БД (выполняется один раз)
def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Создаем таблицу, если она не существует
    cursor.execute('''  
        CREATE TABLE IF NOT EXISTS transactions (
            id SERIAL PRIMARY KEY,
            user_id INTEGER REFERENCES users(id) NOT NULL,
            amount DECIMAL(10, 2) NOT NULL,
            transaction_type VARCHAR(20) NOT NULL, -- 'deposit' or 'withdrawal'
            status VARCHAR(20) NOT NULL, -- 'pending', 'completed', 'failed'
            card_last_four VARCHAR(4),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP
        );              
    ''')
    
    # # Проверяем, есть ли данные в таблице
    # cursor.execute('SELECT COUNT(*) FROM charging_stations')
    # if cursor.fetchone()[0] == 0:
    #     # Добавляем тестовые данные
    #     cursor.execute('''
    #     INSERT INTO charging_stations 
    #     (name, address, latitude, longitude, connector_type, current_type, power, status, photo_url, tariff_id)
    #     VALUES 
    #     (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s),
    #     (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s),
    #     (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    #     ''', (
    #         'Station 1', '123 Main St', 55.7558, 37.6176, 'Type 2', 'AC', 22.0, 'active', 'http://example.com/photo1.jpg', 1,
    #         'Station 2', '456 Oak Ave', 55.7600, 37.6200, 'CHAdeMO', 'DC', 50.0, 'active', 'http://example.com/photo2.jpg', 2,
    #         'Station 3', '789 Pine Blvd', 55.7500, 37.6150, 'CCS', 'DC', 100.0, 'maintenance', 'http://example.com/photo3.jpg', 1
    #     ))
    
    conn.commit()
    cursor.close()
    conn.close()


# Генерация JWT токена
def generate_token(user_id):
    payload = {
        'user_id': user_id,
        'exp': datetime.utcnow() + timedelta(days=7)
    }
    return jwt.encode(payload, app.config['SECRET_KEY'], algorithm='HS256')

# Декоратор для проверки JWT токена
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        
        if 'Authorization' in request.headers:
            token = request.headers['Authorization'].split(" ")[1]
        
        if not token:
            return jsonify({'message': 'Token is missing!'}), 401
            
        try:
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
            current_user = data['user_id']
        except:
            return jsonify({'message': 'Token is invalid!'}), 401
            
        return f(current_user, *args, **kwargs)
        
    return decorated

# Регистрация пользователя
@app.route('/api/auth/register', methods=['POST'])
def register():
    # Проверка Content-Type
    if not request.is_json:
        return jsonify({'error': 'Content-Type must be application/json'}), 415
    
    data = request.get_json()
    
    # Валидация входных данных
    if not data:
        return jsonify({'error': 'No data provided'}), 400
        
    required_fields = ['name', 'email', 'password']
    for field in required_fields:
        if field not in data:
            return jsonify({'error': f'Missing required field: {field}'}), 400
    
    if len(data['password']) < 6:
        return jsonify({'error': 'Password must be at least 6 characters'}), 400
    
    # Хеширование пароля (исправленная версия)
    hashed_password = generate_password_hash(data['password'])
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        cursor.execute('''
            INSERT INTO users (name, email, password, phone, photo_url)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
        ''', (
            data['name'],
            data['email'],
            hashed_password,
            data.get('phone'),
            data.get('photo_url')
        ))
        
        user_id = cursor.fetchone()[0]
        conn.commit()
        
        # Генерация токена
        token = generate_token(user_id)
        
        return jsonify({
            'message': 'Registration successful',
            'user_id': user_id,
            'token': token
        }), 201
        
    except psycopg2.IntegrityError as e:
        conn.rollback()
        if 'users_email_key' in str(e):
            return jsonify({'error': 'Email already exists'}), 409
        return jsonify({'error': 'Database integrity error'}), 400
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500
        
    finally:
        cursor.close()
        conn.close()


@app.route('/api/stations/<int:station_id>/reserve', methods=['POST'])
@token_required
def reserve_station(current_user, station_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Проверяем текущий статус станции
        cursor.execute('''
            SELECT status, reserved_by FROM charging_stations WHERE id = %s
        ''', (station_id,))
        
        station = cursor.fetchone()
        
        if not station:
            return jsonify({'error': 'Station not found'}), 404
            
        current_status = station[0]
        reserved_by = station[1]
        
        if current_status != 'free':
            return jsonify({
                'error': 'Station is not available for reservation',
                'current_status': current_status,
                'reserved_by': reserved_by
            }), 409
        
        # 2. Обновляем статус станции и записываем ID пользователя
        cursor.execute('''
            UPDATE charging_stations 
            SET status = 'reserved', reserved_by = %s
            WHERE id = %s
            RETURNING id, status, reserved_by
        ''', (current_user, station_id))
        
        updated_station = cursor.fetchone()
        
    
        
       
        
        conn.commit()
        
        return jsonify({
            'message': 'Station reserved successfully',
            'station_id': updated_station[0],
            'new_status': updated_station[1],
            'reserved_by': updated_station[2]
        }), 200
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
        
    finally:
        cursor.close()
        conn.close()




@app.route('/api/stations/<int:station_id>/cancel', methods=['POST'])
@token_required
def cancel_reservation(current_user, station_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Проверяем, что станция зарезервирована текущим пользователем
        cursor.execute('''
            SELECT reserved_by FROM charging_stations 
            WHERE id = %s AND status = 'reserved'
        ''', (station_id,))
        
        station = cursor.fetchone()
        
        if not station:
            return jsonify({'error': 'Station is not reserved'}), 400
            
        if station[0] != current_user:
            return jsonify({'error': 'You are not the reserving user'}), 403
        
        # 2. Обновляем статус станции
        cursor.execute('''
            UPDATE charging_stations 
            SET status = 'free', reserved_by = NULL
            WHERE id = %s
            RETURNING id, status
        ''', (station_id,))
        
        updated_station = cursor.fetchone()
        
    
        
        conn.commit()
        
        return jsonify({
            'message': 'Reservation cancelled successfully',
            'station_id': updated_station[0],
            'new_status': updated_station[1],
        }), 200
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
        
    finally:
        cursor.close()
        conn.close()


@app.route('/api/balance/replenish', methods=['POST'])
@token_required
def replenish_balance(current_user):
    try:
        data = request.get_json()
        
        # Валидация данных
        required_fields = ['amount', 'card_number', 'expiry_date', 'cvv', 'card_holder']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        try:
            amount = float(data['amount'])
            if amount <= 0:
                return jsonify({'error': 'Amount must be positive'}), 400
        except ValueError:
            return jsonify({'error': 'Invalid amount format'}), 400
        
        # Здесь должна быть реальная логика обработки платежа через платежный шлюз
        # Для примера просто имитируем успешную оплату
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        try:
            # 1. Создаем запись о транзакции
            cursor.execute('''
                INSERT INTO transactions 
                (user_id, amount, transaction_type, status, card_last_four)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
            ''', (
                current_user,
                amount,
                'deposit',
                'completed',
                data['card_number'][-4:]  # сохраняем последние 4 цифры карты
            ))
            
            transaction_id = cursor.fetchone()[0]
            
            # 2. Обновляем баланс пользователя
            cursor.execute('''
                UPDATE users 
                SET balance = balance + %s 
                WHERE id = %s
                RETURNING balance
            ''', (amount, current_user))
            
            new_balance = cursor.fetchone()[0]
            
            # 3. Обновляем статус транзакции как завершенной
            cursor.execute('''
                UPDATE transactions 
                SET completed_at = CURRENT_TIMESTAMP 
                WHERE id = %s
            ''', (transaction_id,))
            
            conn.commit()
            
            return jsonify({
                'message': 'Balance replenished successfully',
                'new_balance': float(new_balance),
                'transaction_id': transaction_id
            }), 200
            
        except Exception as e:
            conn.rollback()
            return jsonify({'error': f'Database error: {str(e)}'}), 500
            
        finally:
            cursor.close()
            conn.close()
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/balance', methods=['GET'])
@token_required
def get_balance(current_user):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT balance FROM users WHERE id = %s
        ''', (current_user,))
        
        balance = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if balance:
            return jsonify({'balance': float(balance[0])}), 200
        else:
            return jsonify({'error': 'User not found'}), 404
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Авторизация пользователя
@app.route('/api/auth/login', methods=['POST'])
def login():
    try:
        data = request.get_json()
        
        if not data or not data.get('email') or not data.get('password'):
            return jsonify({'error': 'Email and password required'}), 400
            
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute('''
        SELECT id, password FROM users WHERE email = %s
        ''', (data['email'],))
        
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not user:
            return jsonify({'error': 'Invalid credentials'}), 401
            
        if check_password_hash(user['password'], data['password']):
            token = generate_token(user['id'])
            
            return jsonify({
                'message': 'Logged in successfully',
                'token': token,
                'user_id': user['id']
            }), 200
        else:
            return jsonify({'error': 'Invalid credentials'}), 401
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Получение информации о текущем пользователе
@app.route('/api/auth/me', methods=['GET'])
@token_required
def get_current_user(current_user):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute('''
        SELECT id, name, email, phone, balance, photo_url 
        FROM users WHERE id = %s
        ''', (current_user,))
        
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if user:
            # Убираем чувствительные данные перед отправкой
            user.pop('password', None)
            return jsonify(user), 200
        else:
            return jsonify({'error': 'User not found'}), 404
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# Маршрут для получения списка всех зарядных станций
@app.route('/api/stations', methods=['GET'])
def get_stations():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Базовый запрос
        base_query = sql.SQL('SELECT * FROM charging_stations')
        params = []
        
        # Параметры фильтрации
        filters = {
            'connector_type': request.args.get('connector_type'),
            'current_type': request.args.get('current_type'),
            'min_power': request.args.get('min_power'),
            'status': request.args.get('status')
        }
        
        # Добавляем условия фильтрации
        conditions = []
        for key, value in filters.items():
            if value:
                if key == 'min_power':
                    conditions.append(sql.SQL('power >= {}').format(sql.Literal(value)))
                else:
                    conditions.append(sql.SQL('{} = {}').format(
                        sql.Identifier(key),
                        sql.Literal(value)
                    ))
        
        if conditions:
            query = sql.SQL(' ').join([base_query, sql.SQL('AND '), sql.SQL(' AND ').join(conditions)])
        else:
            query = base_query
        
        # Выполняем запрос
        cursor.execute(query)
        stations = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify({'stations': stations}), 200
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Маршрут для получения информации о конкретной станции
@app.route('/api/stations/<int:station_id>', methods=['GET'])
def get_station(station_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute(
            'SELECT * FROM charging_stations WHERE id = %s',
            (station_id,)
        )
        station = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if station:
            return jsonify(station), 200
        else:
            return jsonify({'error': 'Station not found'}), 404
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Маршрут для добавления новой станции
@app.route('/api/stations', methods=['POST'])
def add_station():
    try:
        data = request.get_json()
        
        required_fields = ['name', 'address', 'latitude', 'longitude', 
                          'connector_type', 'current_type', 'power', 'status']
        
        if not all(field in data for field in required_fields):
            return jsonify({'error': 'Missing required fields'}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
        INSERT INTO charging_stations 
        (name, address, latitude, longitude, connector_type, current_type, power, status, photo_url, tariff_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING id
        ''', (
            data['name'],
            data['address'],
            data['latitude'],
            data['longitude'],
            data['connector_type'],
            data['current_type'],
            data['power'],
            data['status'],
            data.get('photo_url'),
            data.get('tariff_id')
        ))
        
        station_id = cursor.fetchone()[0]
        conn.commit()
        
        cursor.close()
        conn.close()
        
        return jsonify({'id': station_id}), 201
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stations/<int:station_id>/start', methods=['POST'])
@token_required
def start_charging(current_user, station_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Проверяем статус станции
        cursor.execute(
            "SELECT status, reserved_by FROM charging_stations WHERE id=%s FOR UPDATE",
            (station_id,)
        )
        result = cursor.fetchone()
        
        if not result:
            return jsonify({"status": "error", "message": "Station not found"}), 404
        
        status = result[0]
        reserved_by = result[1]
        
        # Проверяем, что станция свободна или зарезервирована текущим пользователем
        if status not in ['free', 'reserved']:
            return jsonify({"status": "error", "message": f"Station is {status}"}), 400
        elif status == 'reserved' and reserved_by != current_user:
            return jsonify({"status": "error", "message": "Station is reserved by another user"}), 403
        
        # 2. Обновляем статус станции
        cursor.execute(
            "UPDATE charging_stations SET status='busy' WHERE id=%s",
            (station_id,)
        )
        
        # 3. Создаем запись о сессии
        cursor.execute(
            """INSERT INTO sessions (station_id, user_id, start_time, initial_electricity_meter)
            VALUES (%s, %s, %s, 0) RETURNING id""",
            (station_id, current_user, datetime.now())
        )
        session_id = cursor.fetchone()[0]
        
        conn.commit()
        
        # 4. Отправляем команду станции начать зарядку
        if not station_manager.send_command(station_id, {
            "action": "start_charging",
            "session_id": session_id,
            "user_id": current_user
        }):
            return jsonify({"status": "error", "message": "Station is not connected"}), 400
        
        return jsonify({
            "status": "success",
            "session_id": session_id,
            "message": "Charging started"
        }), 200
        
    except Exception as e:
        conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

@app.route('/api/stations/<int:station_id>/stop', methods=['POST'])
@token_required
def stop_charging(current_user, station_id):
    try:
        data = request.get_json()
        energy_consumed = float(data.get('energy_consumed', 0))
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Проверяем статус станции
        cursor.execute(
            "SELECT status FROM charging_stations WHERE id=%s FOR UPDATE",
            (station_id,)
        )
        result = cursor.fetchone()
        
        if not result:
            return jsonify({"status": "error", "message": "Station not found"}), 404
        
        if result[0] != 'busy':
            return jsonify({"status": "error", "message": "Station is not charging"}), 400
        
        # 2. Проверяем, что текущий пользователь начал сессию
        cursor.execute(
            """SELECT id FROM sessions 
            WHERE station_id=%s AND user_id=%s AND end_time IS NULL""",
            (station_id, current_user)
        )
        session = cursor.fetchone()
        
        if not session:
            return jsonify({"status": "error", "message": "No active session for this user"}), 403
        
        # 3. Обновляем статус станции
        cursor.execute(
            """UPDATE charging_stations 
            SET status='free', reserved_by=NULL 
            WHERE id=%s""",
            (station_id,)
        )
        
        # 4. Обновляем сессию
        cursor.execute(
            """UPDATE sessions SET 
            end_time=%s, 
            energy_consumed=%s
            WHERE station_id=%s AND user_id=%s AND end_time IS NULL""",
            (datetime.now(), energy_consumed, station_id, current_user)
        )
        
        conn.commit()
        
        # 5. Отправляем команду станции остановить зарядку
        if not station_manager.send_command(station_id, {
            "action": "stop_charging",
            "user_id": current_user,
        }):
            return jsonify({"status": "error", "message": "Station is not connected"}), 400
        
        return jsonify({
            "status": "success", 
            "message": "Charging stopped",
            "energy_consumed": energy_consumed
        }), 200
        
    except Exception as e:
        conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

def start_socket_server(ip, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((ip, port))
    sock.listen(5)
    print(f"Socket server listening on {ip, port}")
    
    def handle_client(client_socket, addr):
        try:
            while True:
                data = client_socket.recv(1024)
                if not data:
                    break
                
                try:
                    request = json.loads(data.decode('utf-8'))
                    response = process_socket_request(request, client_socket)
                    client_socket.sendall(json.dumps(response).encode('utf-8'))
                except json.JSONDecodeError:
                    response = {"status": "error", "message": "Invalid JSON"}
                    client_socket.sendall(json.dumps(response).encode('utf-8'))
        except ConnectionResetError:
            print(f"Client {addr} disconnected")
        finally:
            # Удаляем соединение при отключении
            for station_id, sock in list(station_manager.connections.items()):
                if sock == client_socket:
                    station_manager.remove_connection(station_id)
                    break
            client_socket.close()
    
    def process_socket_request(request, client_socket):
        action = request.get("action")
        station_id = request.get("station_id")
        
        if action == "init":
            print(f"New connection from Station(id={station_id})")
            station_manager.add_connection(station_id, client_socket)
            return {"status": "success", "message": "Connection established"}
            
        elif action == "register_command":
            station_manager.add_command_connection(station_id, client_socket)
            return {"status": "success", "message": "Command channel registered"}
            
        elif action == "heartbeat":
            conn = get_db_connection()
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        "UPDATE charging_stations SET last_connection=%s WHERE id=%s",
                        (datetime.now(), station_id)
                    )
                    conn.commit()
                    return {"status": "success"}
            except Exception as e:
                return {"status": "error", "message": str(e)}
            finally:
                conn.close()
                
        elif action == "update":
            energy_consumed = request.get("energy_consumed", 0)
            user_id = request.get("user_id")
            session_id = request.get("session_id")
            
            conn = get_db_connection()
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        """UPDATE sessions SET 
                        energy_consumed=%s
                        WHERE id=%s AND station_id=%s AND user_id=%s""",
                        (energy_consumed, session_id, station_id, user_id)
                    )
                    conn.commit()
                    return {"status": "success"}
            except Exception as e:
                return {"status": "error", "message": str(e)}
            finally:
                conn.close()
                
        else:
            return {"status": "error", "message": "Unknown action"}
    
    try:
        while True:
            client_socket, addr = sock.accept()
            client_thread = threading.Thread(
                target=handle_client,
                args=(client_socket, addr),
                daemon=True
            )
            client_thread.start()
    except KeyboardInterrupt:
        print("Shutting down socket server...")
    finally:
        sock.close()



if __name__ == '__main__':
    init_db()
    print("Flask API listening on ('0.0.0.0', 5000)")
    app.run(host='0.0.0.0', port=5000, debug=True)
    socket_thread = threading.Thread(target=start_socket_server('0.0.0.0', 9090), daemon=True)
    socket_thread.start()
    
    
