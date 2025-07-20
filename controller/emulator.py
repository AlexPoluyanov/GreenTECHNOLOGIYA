import socket
import json
import time
import threading
from datetime import datetime

class ChargingStation:
    def __init__(self, station_id, server_host='localhost', server_port=9090):
        self.station_id = station_id
        self.server_host = server_host
        self.server_port = server_port
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.command_socket = None
        self.power = 0  # kW
        self.power_consumption = 0  # kWh
        self.status = "offline"
        self.connected = False
        self.current_session = None
        self.heartbeat_active = False
        self.heartbeat_rate = 30
        self.update_interval = 15  # seconds
        self.socket_lock = threading.Lock()
        self.energy_thread_active = False
        self.energy_thread = None

    def energy_counter(self, session_id):
        """Метод для подсчета потребленной энергии в отдельном потоке"""
        while self.energy_thread_active and self.current_session and self.current_session["id"] == session_id:
            now = datetime.now()
            time_elapsed = (now - self.current_session["start_time"]).total_seconds()
            
            # Рассчитываем потребленную энергию (кВт * часы)
            energy = self.power * (time_elapsed / 3600)
            
            # Обновляем показания
            with threading.Lock():
                self.current_session["energy_consumed"] = energy
            
            time.sleep(1)  # Обновляем каждую секунду


    def connect_to_server(self):
        try:
            # Основное соединение для heartbeat и команд
            self.socket.connect((self.server_host, self.server_port))
            
            # Отдельное соединение для получения команд от сервера
            self.command_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.command_socket.connect((self.server_host, self.server_port))
            
            response = self.send_request({
                "action": "register_command",
                "station_id": self.station_id
            }, sock=self.command_socket)
            

            print(response)
            if not response or response.get("status") != "success":
                print("Failed to register command channel")
                return False
            
            if self.initialize_station():
                self.connected = True
                self.start_heartbeat()
                return True
            return False
        except Exception as e:
            print(f"Connection error: {e}")
            return False

    def initialize_station(self):
        response = self.send_request({
            "action": "init",
            "station_id": self.station_id
        })
        
        if response.get("status") == "success":
            self.power = response.get("power")
            self.power_consumption = response.get("power_consumption")
            self.status = response.get("station_status")
            if self.status == "busy":
                session_info = response.get("current_session")
                if session_info:
                    start_time = datetime.strptime(session_info["start_time"], "%Y-%m-%d %H:%M:%S")
                    time_elapsed = (datetime.now() - start_time).total_seconds()
                
                    # Пересчитываем энергию с момента начала зарядки
                    energy_consumed = self.power * (time_elapsed / 3600)
                    self.current_session = {
                        "id": session_info["id"],
                        "start_time": start_time,
                        "user_id": session_info["user_id"],
                        "energy_consumed": energy_consumed,
                        "meter_start_readings": session_info["initial_electricity_meter"]
                    }
                    # Запускаем счетчик энергии
                    self.energy_thread_active = True
                    self.energy_thread = threading.Thread(
                        target=self.energy_counter,
                        args=(self.current_session["id"],),
                        daemon=True
                    )
                    self.energy_thread.start()
            
            print(f"Station initialized. Power: {self.power} kW, Power consumption: {self.power_consumption}, Status: {self.status}")
            return True
        print("Failed to initialize station:", response.get("message", "Unknown error"))
        return False
    
    def start_heartbeat(self):
        self.heartbeat_active = True
    
        def heartbeat_loop():
            while self.heartbeat_active and self.connected:
                try:
                    if self.current_session:
                        self.heartbeat_rate = 15
                        # Во время зарядки отправляем update вместо heartbeat
                        response = self.send_request({
                            "action": "update",
                            "station_id": self.station_id,
                            "user_id": self.current_session['user_id'],
                            "session_id": self.current_session['id'],
                            "energy_consumed": self.current_session['energy_consumed']
                        })
                    else:
                        self.heartbeat_rate = 30
                        # Когда нет активной сессии - обычный heartbeat
                        response = self.send_request({
                            "action": "heartbeat",
                            "station_id": self.station_id
                        })
                    
                    if not response or response.get("status") != "success":
                        print("Heartbeat/update failed")
                        self.connected = False
                except Exception as e:
                    print(f"Heartbeat/update error: {e}")
                    self.connected = False
                
                time.sleep(self.heartbeat_rate)
        
        threading.Thread(target=heartbeat_loop, daemon=True).start()


    def send_request(self, request, sock=None):
        if sock is None:
            sock = self.socket
        try:
            with self.socket_lock:
                sock.sendall(json.dumps(request).encode('utf-8'))
                response = sock.recv(1024)
                return json.loads(response.decode('utf-8'))
        except Exception as e:
            print(f"Request error: {e}")
            return None
        
    def start_charging_local(self, session_id, user_id):
            if self.current_session:
                return False
        
            self.current_session = {
                "id": session_id,
                "start_time": datetime.now(),
                "user_id": user_id,
                "energy_consumed": 0,
                "meter_start_readings": self.power_consumption,
            }
            self.status = "busy"
            print(f"Started charging session {session_id}")
            

            self.energy_thread_active = True
            # Запускаем поток для обновления потребленной энергии
            
            self.energy_thread = threading.Thread(
            target=self.energy_counter, 
            args=(session_id,),
            daemon=True
            )
            self.energy_thread.start()
            return True

    def stop_charging_local(self, user_id):
        if not self.current_session:
            return False
        
        if user_id != self.current_session['user_id']:
            print("Can't cancel other user use station")
            return False 


        self.energy_thread_active = False
        if self.energy_thread:
            self.energy_thread.join(timeout=1)  
        # Рассчитываем финальное потребление
        final_energy = self.current_session["energy_consumed"] + self.current_session["meter_start_readings"] 
        duration = (datetime.now() - self.current_session["start_time"]).total_seconds()
    
        print(f"\nCharging session {self.current_session['id']} completed")
        print(f"User ID: {self.current_session['user_id']}")
        print(f"Duration: {duration:.2f} seconds")
        print(f"Energy consumed: {self.current_session['energy_consumed']} kWh")
        

        self.current_session = None
        self.status = "free"
        self.power_consumption = final_energy
        return True
        # # Отправляем данные на сервер
        # response = self.send_request({
        #     "action": "stop_charging",
        #     "station_id": self.station_id,
        #     "energy_consumed": final_energy,
        #     "session_id": self.current_session["id"]
        # })
        
        # if response and response.get("status") == "success":
        #     self.current_session = None
        #     self.status = "free"
        #     return True
        # else:
        #     print("Failed to report charging stop to server")
        #     return False    

    def process_command(self, command):
        action = command.get("action")
        
        if action == "start_charging":
            print("\nReceived START CHARGING command from server")
            if not self.current_session:
                session_id = command.get("session_id")
                user_id = command.get("user_id")
                if self.start_charging_local(session_id, user_id):
                    print("Charging started successfully")
                else:
                    print("Failed to start charging")
            else:
                print("Already charging - ignoring command")
        
        elif action == "stop_charging":
            print("\nReceived STOP CHARGING command from server")
            user_id = command.get("user_id")
            if self.current_session:
                if self.stop_charging_local(user_id):
                    print(f"Charging stopped.")
                else:
                    print("Failed to stop charging")
            else:
                print("Not charging - ignoring command")
        

        elif action == "set_power":
            new_power = command.get("power")
            if new_power is not None:
                self.power = new_power
                print(f"\nPower updated to {new_power} kW by server command")
        
        else:
            print(f"Unknown command: {action}")

    

    def listen_for_commands(self):
        """Слушает команды от сервера на отдельном соединении"""
        while self.connected:
            try:
                data = self.command_socket.recv(1024)
                if not data:
                    print("Command connection closed by server")
                    self.connected = False
                    break
                    
                command = json.loads(data.decode('utf-8'))
                self.process_command(command)
            except ConnectionResetError:
                print(f"Command listener error: connection lost")
                self.connected = False
                break
            except Exception as e:
                print(f"Command listener error: {e}")
                self.connected = False
                break

    def run(self):
        if not self.connect_to_server():
            return

        # Запускаем поток для прослушивания команд
        command_thread = threading.Thread(target=self.listen_for_commands, daemon=True)
        command_thread.start()

        try:
            print("\nStation ready. Waiting for commands from server...")
            print("Type 'status' to check current state")
            
            while self.connected:
                cmd = input().strip().lower()
                
                if cmd == "status":
                    print(f"\nStation {self.station_id}")
                    print(f"Power: {self.power} kW")
                    print(f"Power consumption: {self.power_consumption} kW")
                    print(f"Status: {self.status}")
                    if self.current_session:
                        duration = (datetime.now() - self.current_session["start_time"]).total_seconds()
                        print(f"Charging session: {self.current_session['id']}")
                        
                        print(f"Duration: {duration:.2f} seconds")
                        print(f"Power recived: {self.current_session['energy_consumed']}")
                
                time.sleep(0.1)
                
        except KeyboardInterrupt:
            print("Shutting down...")
        finally:
            self.heartbeat_active = False
            self.connected = False
            if self.socket:
                self.socket.close()
            if self.command_socket:
                self.command_socket.close()

if __name__ == "__main__":
    station_id = int(input("Enter station ID: "))
    station = ChargingStation(station_id)
    station.run()