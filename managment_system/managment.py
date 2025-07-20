import socket
import threading
import json
import psycopg2
from psycopg2 import pool
from datetime import datetime

class ChargingServer:
    def __init__(self):
         # Основной порт для станций
        self.station_host = '0.0.0.0'
        self.station_port = 9090
        
        # Порт для API команд от бэкенда
        self.api_host = '0.0.0.0'
        self.api_port = 9091

        self.station_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.station_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        self.api_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.api_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        self.connections = {}  
        self.command_sockets = {}  
        # Пул соединений PostgreSQL
        self.db_pool = psycopg2.pool.SimpleConnectionPool(
            minconn=1,
            maxconn=10,
            host="localhost",
            database="postgres",
            user="postgres",
            password="postgres"
        )
        
        self.init_db()

    def init_db(self):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS sessions (
                        id SERIAL PRIMARY KEY,
                        station_id INTEGER REFERENCES charging_stations(id),
						user_id INTEGER REFERENCES users(id),
                        start_time TIMESTAMP NOT NULL,
                        end_time TIMESTAMP,
                        energy_consumed FLOAT,
						initial_electricity_meter FLOAT NOT NULL,
						end_electricity_meter FLOAT
                    );
                """)
                conn.commit()
        finally:
            self.db_pool.putconn(conn)

    def handle_station_client(self, client_socket, addr):
        try:
            while True:
                data = client_socket.recv(1024)
                if not data:
                    break
                try:
                    request = json.loads(data.decode('utf-8'))
                    response = self.process_station_request(request, client_socket)
                    client_socket.sendall(json.dumps(response).encode('utf-8'))
                except json.JSONDecodeError:
                    response = {"status": "error", "message": "Invalid JSON"}
                    client_socket.sendall(json.dumps(response).encode('utf-8'))
        except ConnectionResetError:
            print(f"Station client {addr} disconnected")
        finally:
            # Удаляем соединение при отключении
            for station_id, sock in list(self.connections.items()):
                if sock == client_socket:
                    self.connections.pop(station_id, None)
                    self.command_sockets.pop(station_id, None)
                    break
            client_socket.close()

    def process_station_request(self, request, client_socket):
        action = request.get("action")
        station_id = request.get("station_id")

        if action == "init":
            print(f"New connection from Station(id={station_id})")
            return self.init_station(station_id, client_socket)
        elif action == "heartbeat":
            return self.update_heartbeat(station_id)
        elif action == "get_status":
            return self.get_station_status(station_id)
        elif action == "update":
            energy_consumed = request.get("energy_consumed", 0)
            user_id = request.get("user_id")
            session_id = request.get("session_id")
            return self.update_charging_session(station_id, user_id, session_id, energy_consumed)
        elif action == "register_command":
            # Регистрируем отдельное соединение для команд
            self.command_sockets[station_id] = client_socket
            return {"status": "success", "message": "Command channel registered"}
        else:
            return {"status": "error", "message": "Unknown action"}

    def handle_api_client(self, client_socket, addr):
        try:
            while True:
                data = client_socket.recv(1024)
                if not data:
                    break
                try:
                    request = json.loads(data.decode('utf-8'))
                    response = self.process_api_request(request)
                    client_socket.sendall(json.dumps(response).encode('utf-8'))
                except json.JSONDecodeError:
                    response = {"status": "error", "message": "Invalid JSON"}
                    client_socket.sendall(json.dumps(response).encode('utf-8'))
        except ConnectionResetError:
            print(f"API client {addr} disconnected")
        finally:
            client_socket.close()

    def process_api_request(self, request):
        action = request.get("action")
        station_id = request.get("station_id")
        user_id = request.get("user_id")

        if action == "start_charging":
            return self.start_charging(station_id, user_id)
        elif action == "stop_charging":
            return self.stop_charging(station_id, user_id)
        elif action == "get_status":
            return self.get_station_status(station_id)
        else:
            return {"status": "error", "message": "Unknown action"}


    def init_station(self, station_id, client_socket):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                # Проверяем существует ли станция
                cur.execute("""
                SELECT cs.power, cs.power_consumption, cs.status, 
                       s.id, s.user_id, s.start_time, s.energy_consumed, s.initial_electricity_meter
                FROM charging_stations cs
                LEFT JOIN sessions s ON cs.id = s.station_id AND s.end_time IS NULL
                WHERE cs.id=%s
                """, (station_id,))
                result = cur.fetchone()
                
                if not result:
                    return {"status": "error", "message": "Station not found"}
                    # допилить
                    # Если станции нет, создаем новую
                    # cur.execute(
                    #     "INSERT INTO charging_stations (id, power, status) VALUES (%s, %s, %s)",
                    #     (station_id, 50.0, 'free')  # Значения по умолчанию
                    # )
                    # conn.commit()
                    # power = 50.0
                    # status = 'free'
            
                power, power_consumption, status = result[0], result[1], result[2]
                session_data = None
                
                # Если есть активная сессия
                if status == 'busy' and result[3]:
                    session_data = {
                        "id": result[3],
                        "user_id": result[4],
                        "start_time": result[5].strftime("%Y-%m-%d %H:%M:%S"),
                        "energy_consumed": float(result[6]),
                        "initial_electricity_meter": float(result[7])
                    }
                
                response = {
                    "status": "success", 
                    "message": "Station initialized", 
                    "power": float(power),
                    "power_consumption": float(power_consumption),
                    "station_status": status
                }
                
                if session_data:
                    response["current_session"] = session_data
                
                conn.commit()
            
            self.connections[station_id] = client_socket
            return response
        except Exception as e:
            return {"status": "error", "message": str(e)}
        finally:
            self.db_pool.putconn(conn)

    def update_heartbeat(self, station_id):
        conn = self.db_pool.getconn()
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
            self.db_pool.putconn(conn)

    def update_charging_session(self, station_id, user_id, session_id, energy_consumed):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                # Обновляем время последнего соединения и потребленную энергию
                cur.execute(
                    """UPDATE charging_stations 
                    SET last_connection=%s 
                    WHERE id=%s""",
                    (datetime.now(), station_id)
                )
                
                # Обновляем сессию
                cur.execute(
                    """UPDATE sessions SET 
                    energy_consumed=%s
                    WHERE station_id=%s AND user_id=%s AND id=%s""",
                    (energy_consumed, station_id, user_id, session_id)
                )
                
                conn.commit()
                return {"status": "success"}
        except Exception as e:
            conn.rollback()
            return {"status": "error", "message": str(e)}
        finally:
            self.db_pool.putconn(conn)


    def get_station_status(self, station_id):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT status FROM charging_stations WHERE id=%s",
                    (station_id,)
                )
                result = cur.fetchone()
                if result:
                    return {
                        "status": "success", 
                        "station_status": result[0]
                    }
                return {"status": "error", "message": "Station not found"}
        except Exception as e:
            return {"status": "error", "message": str(e)}
        finally:
            self.db_pool.putconn(conn)

    def start_charging(self, station_id, user_id):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                # Проверяем статус станции
                cur.execute(
                    "SELECT status, power_consumption, reserved_by FROM charging_stations WHERE id=%s FOR UPDATE",
                    (station_id,)
                )
                result = cur.fetchone()
                
                if not result:
                    return {"status": "error", "message": "Station not found"}
                
                status = result[0]
                power_consumption = result[1]
                reserved_by = result[2]
                if status.strip() not in ['free', 'reserved']:
                    return {"status": "error", "message": f"Station is {status}"}
                elif status == 'reserved':
                    if int(user_id) != int(reserved_by):
                        return {"status": "error", "message": f"Station is reserved by other user"}
                elif status == 'busy':
                    if int(user_id) != int(reserved_by):
                        return {"status": "error", "message": f"Station is used by other user"}
                    return {"status": "error", "message": f"Charging is already start"}
                # Обновляем статус
                cur.execute(
                    "UPDATE charging_stations SET status='busy', using_by=%s WHERE id=%s",
                    (user_id, station_id,)
                )


                # Создаем запись о сессии
                cur.execute(
                    """INSERT INTO sessions (station_id, user_id, start_time, initial_electricity_meter)
                    VALUES (%s, %s, %s, %s) RETURNING id""",
                    (station_id, user_id, datetime.now(), power_consumption)
                )
                session_id = cur.fetchone()[0]
                
                conn.commit()
                
                # Отправляем команду станции начать зарядку
                self.send_command_to_station(station_id, {
                    "action": "start_charging",
                    "session_id": session_id,
                    "status": "busy",
                    "user_id": user_id,
                })
                
                return {
                    "status": "success",
                    "session_id": session_id,
                    "message": "Charging started"
                }
        except Exception as e:
            conn.rollback()
            return {"status": "error", "message": str(e)}
        finally:
            self.db_pool.putconn(conn)

    def stop_charging(self, station_id, user_id):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                # Проверяем статус станции
                cur.execute(
                    "SELECT status, power, using_by FROM charging_stations WHERE id=%s",
                    (station_id,)
                )
                result = cur.fetchone()
                power = result[1]
                using_by = result[2]
                if not result:
                    return {"status": "error", "message": "Station not found"}
                
                if result[0] != 'busy':
                    return {"status": "error", "message": "Station is not charging"}
                
                if user_id != using_by:
                    return {"status": "error", "message": "Station in use by other user"}
                
                cur.execute(
                    """
                    SELECT initial_electricity_meter, start_time FROM sessions WHERE
                    station_id = %s AND user_id = %s AND end_time IS NULL
                    """, (station_id, user_id)
                )
                
                result = cur.fetchone()
                if not result:
                    return {"status": "error", "message": "Session not found"}
                
                initial_electricity_meter = result[0]
                start_time = result[1]
                
                
                duration = (datetime.now() - start_time).total_seconds()
                energy_consumed = float(power) * (duration / 3600)
                # Обновляем статус
                cur.execute(
                    """UPDATE charging_stations 
                    SET status='free', reserved_by=NULL, using_by=NULL, power_consumption=power_consumption+%s 
                    WHERE id=%s""",
                    (energy_consumed, station_id)
                )
                
                # Обновляем сессию
                cur.execute(
                    """UPDATE sessions SET 
                    end_time=%s, 
                    energy_consumed=%s, 
                    end_electricity_meter=%s
                    WHERE station_id=%s AND user_id=%s AND end_time IS NULL""",
                    (datetime.now(), energy_consumed, initial_electricity_meter+energy_consumed,  station_id, user_id)
                )
                
                conn.commit()
                
                # Отправляем команду станции остановить зарядку
                self.send_command_to_station(station_id, {
                    "action": "stop_charging",
                    "user_id": user_id,
                })
                
                return {"status": "success", "message": "Charging stopped"}
        except Exception as e:
            conn.rollback()
            return {"status": "error", "message": str(e)}
        finally:
            self.db_pool.putconn(conn)

    def send_command_to_station(self, station_id, command):
        """Отправляет команду на станцию через отдельное соединение"""
        try:
            if station_id in self.command_sockets:
                sock = self.command_sockets[station_id]
                sock.sendall(json.dumps(command).encode('utf-8'))
                return True
            else:
                print(f"No command socket for station {station_id}")
                return False
        except Exception as e:
            print(f"Error sending command to station {station_id}: {e}")
            # Удаляем нерабочее соединение
            self.command_sockets.pop(station_id, None)
            return False

    def command_interface(self):
        """Интерфейс для ввода команд оператором"""
        while True:
            print("\nAvailable commands:")
            print("1. List stations")
            print("2. Start charging on station")
            print("3. Stop charging on station")
            print("4. Set station power")
            print("5. Get station status")
            
            try:
                choice = input("Enter command number: ")
                station_id = 5
                user_id = 1
                if choice == "1":
                    self.list_stations()
                elif choice == "2":
                    station_id = int(input("Enter station ID: "))
                    user_id = int(input("Enter user ID: "))
                    self.start_charging_ui(station_id, user_id)
                elif choice == "3":
                    station_id = int(input("Enter station ID: "))
                    user_id = int(input("Enter user ID: "))
                    self.stop_charging_ui(station_id, user_id)
                elif choice == "4":
                    station_id = int(input("Enter station ID: "))
                    power = float(input("Enter new power (kW): "))
                    self.set_station_power(station_id, power)
                elif choice == "5":
                    station_id = int(input("Enter station ID: "))
                    self.get_station_status_ui(station_id)
                else:
                    print("Invalid choice")
            except Exception as e:
                print(f"Error: {e}")

    def list_stations(self):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT id, power, status FROM charging_stations ORDER BY id")
                stations = cur.fetchall()
                
                print("\nConnected stations:")
                for station in stations:
                    connected = "Yes" if station[0] in self.connections else "No"
                    print(f"ID: {station[0]}, Power: {station[1]} kW, Status: {station[2]}, Connected: {connected}")
        finally:
            self.db_pool.putconn(conn)

    def start_charging_ui(self, station_id, user_id):
        if station_id not in self.connections:
            print(f"Station {station_id} is not connected")
            return
            
        response = self.start_charging(station_id, user_id)
        print(response)
        if response["status"] == "success":
            print(f"Started charging on station {station_id}")
        else:
            print(f"Failed to start charging: {response['message']}")

    def stop_charging_ui(self, station_id, user_id):
        if station_id not in self.connections:
            print(f"Station {station_id} is not connected")
            return
            
        # Получаем текущую сессию для расчета энергии
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:

                cur.execute(
                    "SELECT status FROM charging_stations WHERE id=%s",
                    (station_id,)
                )
                result = cur.fetchone()
                if not result:
                    print({"status": "error", "message": "Station not found"})
                    return
                if result[0] != 'busy':
                    print({"status": "error", "message": "Station is not charging"})
                    return
                cur.execute(
                    """
                    SELECT initial_electricity_meter FROM sessions WHERE
                    station_id = %s AND user_id = %s AND end_time IS NULL
                    """, (station_id, user_id)
                )
                
                result = cur.fetchone()
                if not result:
                    print({"status": "error", "message": "Station using by other user"})
                    return
                cur.execute(
                    """SELECT start_time FROM sessions 
                    WHERE station_id=%s AND end_time IS NULL AND user_id=%s""",
                    (station_id, user_id)
                )
                result = cur.fetchone()
                
                if not result:
                    print("No active charging session")
                    return
                
                start_time = result[0]
                duration = (datetime.now() - start_time).total_seconds()
                
                # Получаем мощность станции
                cur.execute(
                    "SELECT power FROM charging_stations WHERE id=%s",
                    (station_id,)
                )
                power = cur.fetchone()[0]
                
  
                energy_consumed = float(power) * (duration / 3600)  # kWh

                response = self.stop_charging(station_id, user_id)
                print(response)
                if response["status"] == "success":
                    print(f"Stopped charging on station {station_id}")
                    print(f"Energy consumed: {round(energy_consumed, 2)} kWh")
                else:
                    print(f"Failed to stop charging: {response['message']}")
        finally:
            self.db_pool.putconn(conn)

    def set_station_power(self, station_id, power):
        conn = self.db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE charging_stations SET power=%s WHERE id=%s",
                    (power, station_id)
                )
                conn.commit()
                
                # Отправляем команду на обновление мощности
                self.send_command_to_station(station_id, {
                    "action": "set_power",
                    "power": power
                })
                
                print(f"Power for station {station_id} set to {power} kW")
        except Exception as e:
            print(f"Error setting power: {e}")
        finally:
            self.db_pool.putconn(conn)

    def get_station_status_ui(self, station_id):
        response = self.get_station_status(station_id)
        if response["status"] == "success":
            print(f"\nStation {station_id} status:")
            print(f"Status: {response['station_status']}")
            print(f"Connected: {'Yes' if station_id in self.connections else 'No'}")
        else:
            print(f"Error: {response['message']}")

    def start(self):
        # Запускаем сервер для станций
        self.station_socket.bind((self.station_host, self.station_port))
        self.station_socket.listen(5)
        print(f"Station server listening on {self.station_host}:{self.station_port}")

        # Запускаем сервер для API команд
        self.api_socket.bind((self.api_host, self.api_port))
        self.api_socket.listen(5)
        print(f"API command server listening on {self.api_host}:{self.api_port}")

        # Поток для обработки соединений от станций
        station_thread = threading.Thread(
            target=self.accept_station_connections,
            daemon=True
        )
        station_thread.start()

        # Поток для обработки API команд
        api_thread = threading.Thread(
            target=self.accept_api_connections,
            daemon=True
        )
        api_thread.start()

        # Основной поток для командного интерфейса
        self.command_interface()

    def accept_station_connections(self):
            try:
                while True:
                    client_socket, addr = self.station_socket.accept()
                    client_thread = threading.Thread(
                        target=self.handle_station_client,
                        args=(client_socket, addr),
                        daemon=True
                    )
                    client_thread.start()
            except KeyboardInterrupt:
                print("Shutting down station server...")

    def accept_api_connections(self):
        try:
            while True:
                client_socket, addr = self.api_socket.accept()
                client_thread = threading.Thread(
                    target=self.handle_api_client,
                    args=(client_socket, addr),
                    daemon=True
                )
                client_thread.start()
        except KeyboardInterrupt:
            print("Shutting down API server...")  


    def command_interface(self):
        """Интерфейс для ввода команд оператором"""
        while True:
            print("\nAvailable commands:")
            print("1. List stations")
            print("2. Start charging on station")
            print("3. Stop charging on station")
            print("4. Set station power")
            print("5. Get station status")
            print("6. Exit")
            
            try:
                choice = input("Enter command number: ")
                if choice == "6":
                    break
                
                 # Для тестирования
                
                if choice == "1":
                    self.list_stations()
                elif choice == "2":
                    station_id = int(input("Enter station ID: "))
                    user_id = int(input("Enter USER ID: ")) 
                    self.start_charging_ui(station_id, user_id)
                elif choice == "3":
                    station_id = int(input("Enter station ID: "))
                    user_id = int(input("Enter USER ID: ")) 
                    self.stop_charging_ui(station_id, user_id)
                elif choice == "4":
                    station_id = int(input("Enter station ID: "))
                    power = float(input("Enter new power (kW): "))
                    self.set_station_power(station_id, power)
                elif choice == "5":
                    station_id = int(input("Enter station ID: "))
                    self.get_station_status_ui(station_id)
                else:
                    print("Invalid choice")
            except Exception as e:
                print(f"Error: {e}")

        self.shutdown()  

    def shutdown(self):
        print("Shutting down servers...")
        self.station_socket.close()
        self.api_socket.close()
        self.db_pool.closeall()    

if __name__ == "__main__":
    server = ChargingServer()
    server.start()