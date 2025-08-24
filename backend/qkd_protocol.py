# backend/qkd_protocol.py
import numpy as np
from qiskit import QuantumCircuit, transpile
from qiskit_aer import AerSimulator

class QKDProtocol:
    """
    BB84 simulado con Qiskit:
    - Usamos pocas qubits por ronda (<= 20) para no chocar límites del backend.
    - Acumulamos rondas hasta alcanzar los bits objetivo.
    """
    def __init__(self, key_length: int = 20):
        # <= 20 para estar por debajo del límite de 29 qubits del backend
        self.key_length = key_length
        self.simulator = AerSimulator()

    def generate_bases(self) -> np.ndarray:
        return np.random.randint(2, size=self.key_length)  # 0=Z, 1=X

    def prepare_qubits(self, alice_bits: np.ndarray, alice_bases: np.ndarray) -> QuantumCircuit:
        qc = QuantumCircuit(self.key_length, self.key_length)
        for i in range(self.key_length):
            if alice_bits[i] == 1:
                qc.x(i)
            if alice_bases[i] == 1:
                qc.h(i)
        return qc

    def measure_with_bases(self, qc: QuantumCircuit, bob_bases: np.ndarray) -> QuantumCircuit:
        for i in range(self.key_length):
            if bob_bases[i] == 1:
                qc.h(i)
        qc.measure(range(self.key_length), range(self.key_length))
        return qc

    def run_bb84_round(self) -> list[int]:
        alice_bits  = np.random.randint(2, size=self.key_length)
        alice_bases = self.generate_bases()
        bob_bases   = self.generate_bases()

        qc = self.prepare_qubits(alice_bits, alice_bases)
        qc = self.measure_with_bases(qc, bob_bases)

        # Transpila sin acoplarla a un device con coupling_map restrictivo
        compiled = transpile(qc, basis_gates=None, optimization_level=0)
        result   = self.simulator.run(compiled, shots=1).result()
        counts   = result.get_counts()
        bitstr   = list(counts.keys())[0]
        measured = np.array([int(b) for b in bitstr[::-1]])

        matching = alice_bases == bob_bases
        sifted   = measured[matching]
        return sifted.tolist()

    def generate_shared_key(self, target_bits: int = 128, max_rounds: int = 100) -> bytes:
        pool: list[int] = []
        for _ in range(max_rounds):
            pool.extend(self.run_bb84_round())
            if len(pool) >= target_bits:
                break
        if len(pool) < target_bits:
            raise RuntimeError("No se alcanzaron los bits requeridos; aumenta max_rounds o key_length.")

        bits = pool[:target_bits]
        # bits -> bytes
        byts = bytearray()
        for i in range(0, target_bits, 8):
            val = 0
            for b in bits[i:i+8]:
                val = (val << 1) | b
            byts.append(val)
        return bytes(byts)
