import SwiftUI
import CoreBluetooth

struct ParentLinkingSheet: View {
    let parentUID: String
    let kk: Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ble = BLELinkingService.shared

    private var shortCode: String { String(parentUID.prefix(8)).uppercased() }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color.green)

                            Text(kk ? "Баланы қосу" : "Подключить ребёнка")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)

                            Text(
                                kk
                                ? "Балаңыз осы экран ашық тұрған кезде жақын маңнан сізді тауып, сұрау жібере алады."
                                : "Пока этот экран открыт, ребёнок рядом сможет найти вас и отправить запрос на привязку."
                            )
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)

                        VStack(spacing: 12) {
                            statusRow(
                                icon: ble.isAdvertising ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right",
                                title: kk ? "BLE таратылымы" : "BLE вещание",
                                value: ble.isAdvertising
                                    ? (kk ? "Іске қосылды" : "Включено")
                                    : (kk ? "Күтілуде" : "Ожидание"),
                                tint: ble.isAdvertising ? .green : .orange
                            )

                            statusRow(
                                icon: "number.circle.fill",
                                title: kk ? "Қысқа код" : "Короткий код",
                                value: shortCode,
                                tint: .blue,
                                monospaced: true
                            )

                            statusRow(
                                icon: "bolt.horizontal.circle.fill",
                                title: kk ? "Bluetooth күйі" : "Состояние Bluetooth",
                                value: bluetoothStateText(ble.peripheralState),
                                tint: ble.peripheralState == .poweredOn ? .green : .orange
                            )
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        if let error = ble.lastErrorMessage, !error.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.orange.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(kk ? "Қосу" : "Привязка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ble.lastErrorMessage = nil
            ble.publishToken(uid: parentUID)
            ble.startAdvertising(uid: parentUID)
        }
        .onDisappear {
            ble.stopAdvertising()
        }
    }

    private func statusRow(
        icon: String,
        title: String,
        value: String,
        tint: Color,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Text(value)
                    .font(monospaced
                          ? .system(size: 16, weight: .bold, design: .monospaced)
                          : .system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()
        }
    }

    private func bluetoothStateText(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return kk ? "Қосулы" : "Включен"
        case .poweredOff: return kk ? "Өшірулі" : "Выключен"
        case .unauthorized: return kk ? "Рұқсат жоқ" : "Нет доступа"
        case .unsupported: return kk ? "Қолданылмайды" : "Не поддерживается"
        case .resetting: return kk ? "Қайта іске қосылуда" : "Перезапуск"
        default: return kk ? "Белгісіз" : "Неизвестно"
        }
    }
}

struct ChildParentLinkSheet: View {
    let childUID: String
    let kk: Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ble = BLELinkingService.shared
    @State private var sentShortCode: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.green)

                        Text(kk ? "Ата-анаға қосылу" : "Подключиться к родителю")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)

                        Text(
                            kk
                            ? "Жақын маңдағы ата-ананы таңдаңыз. Сұрау жіберілген соң ата-ана оны растауы керек."
                            : "Выберите родителя рядом. После отправки запроса родитель должен подтвердить привязку."
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)

                    if let sentShortCode {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(
                                kk
                                ? "Сұрау жіберілді: \(sentShortCode)"
                                : "Запрос отправлен: \(sentShortCode)"
                            )
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                    }

                    if let error = ble.lastErrorMessage, !error.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.orange.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                    }

                    if ble.discoveredDevices.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(kk ? "Ата-ана құрылғысын іздеп жатыр..." : "Ищу устройство родителя...")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(ble.discoveredDevices.sorted { $0.rssi > $1.rssi }) { device in
                                    Button {
                                        ble.lastErrorMessage = nil
                                        ble.sendLinkRequest(deviceShortCode: device.shortCode, childUID: childUID)
                                        sentShortCode = device.shortCode
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: "figure.and.child.holdinghands")
                                                .font(.system(size: 20))
                                                .foregroundStyle(Color.green)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(device.name)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text("\(device.shortCode) · \(device.distance.rawValue)")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white.opacity(0.45))
                                            }

                                            Spacer()

                                            Image(systemName: "arrow.up.right.circle.fill")
                                                .foregroundStyle(.white.opacity(0.35))
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18)
                                                .fill(Color.white.opacity(0.06))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 18)
                                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle(kk ? "Қосу" : "Привязка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ble.lastErrorMessage = nil
            ble.startScan()
        }
        .onDisappear {
            ble.stopScan()
        }
    }
}
