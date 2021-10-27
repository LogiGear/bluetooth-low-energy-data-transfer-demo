//
//  PeripheralViewController.swift
//
//  Created by bangmaple on 18/10/2021.
//  Copyright © 2021 Apple. All rights reserved.
//


import UIKit
import CoreBluetooth
import os

class PeripheralViewController: UIViewController {

    @IBOutlet var textView: UITextView!
    @IBOutlet var advertisingSwitch: UISwitch!
    @IBOutlet var viewImage: [UIImageView]!
    @IBOutlet weak var btnImagePicker: UIButton!

    var peripheralManager: CBPeripheralManager!

    var transferCharacteristic: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    var dataToSend = Data()
    var sendDataIndex: Int = 0

    var imagePicker: ImagePicker!

    override func viewDidLoad() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        super.viewDidLoad()
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)


    }

    @IBAction func openImagePicker(_ sender: UIButton) {
        self.imagePicker.present(from: sender)

    }

    override func viewWillDisappear(_ animated: Bool) {
        peripheralManager.stopAdvertising()
        super.viewWillDisappear(animated)
    }

    @IBAction func showImagePicker(_ sender: UIButton) {
        self.imagePicker.present(from: sender)
    }

    @IBAction func switchChanged(_ sender: Any) {
        if advertisingSwitch.isOn {
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID]])
        } else {
            peripheralManager.stopAdvertising()
        }
    }
    static var sendingEOM = false

    private func convertImageToBase64(image: UIImage) -> String {
        let imageData = image.pngData()
        return imageData!.base64EncodedString(options: Data.Base64EncodingOptions.lineLength64Characters)
    }

    private func sendData() {

		guard let transferCharacteristic = transferCharacteristic else {
			return
		}
		        if PeripheralViewController.sendingEOM {
            let didSend = peripheralManager.updateValue("EOM".data(using: String.Encoding.utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            if didSend {
                PeripheralViewController.sendingEOM = false
                os_log("Sent: EOM")
            }
            return
        }

        if sendDataIndex >= dataToSend.count {
            return
        }

        var didSend = true
        while didSend {

            var amountToSend = dataToSend.count - sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                print(min(amountToSend, mtu))
                amountToSend = min(amountToSend, mtu)
            }

            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))

            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)

            if !didSend {
                return
            }

            let stringFromData = String(data: chunk, encoding: .utf8)
            os_log("Sent %d bytes: %s", chunk.count, String(describing: stringFromData))

            sendDataIndex += amountToSend
            if sendDataIndex >= dataToSend.count {

                PeripheralViewController.sendingEOM = true

                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                             for: transferCharacteristic, onSubscribedCentrals: nil)

                if eomSent {
                    PeripheralViewController.sendingEOM = false
                    os_log("Sent: EOM")
                }
                return
            }
        }
    }

    private func setupPeripheral() {

        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
                                                         properties: [.notify, .writeWithoutResponse],
                                                         value: nil,
                                                         permissions: [.readable, .writeable])

        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)

        transferService.characteristics = [transferCharacteristic]

        peripheralManager.add(transferService)

        self.transferCharacteristic = transferCharacteristic

    }
}

extension PeripheralViewController: CBPeripheralManagerDelegate {
    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {

        advertisingSwitch.isEnabled = peripheral.state == .poweredOn

        switch peripheral.state {
        case .poweredOn:
            os_log("CBManager is powered on")
            setupPeripheral()
        case .poweredOff:
            os_log("CBManager is not powered on")

            return
        case .resetting:
            os_log("CBManager is resetting")
            return
        case .unauthorized:
            if #available(iOS 13.0, *) {
                switch peripheral.authorization {
                case .denied:
                    os_log("You are not authorized to use Bluetooth")
                case .restricted:
                    os_log("Bluetooth is restricted")
                default:
                    os_log("Unexpected authorization")
                }
            } else {
            }
            return
        case .unknown:
            os_log("CBManager state is unknown")
            return
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
            return
        @unknown default:
            os_log("A previously unknown peripheral manager state occurred")
            return
        }
    }

    private func convertB64ToStr(image: UIImage) -> String {
        if let imageData = viewImage[0].image!.jpegData(compressionQuality: 0.25) {
            let base64String = imageData.base64EncodedString()
            return base64String
        }
        return ""
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        os_log("Central subscribed to characteristic")
        dataToSend = convertB64ToStr(image: viewImage[0].image!).data(using: .utf8)!

        //dataToSend = textView.text.data(using: .utf8)!
        sendDataIndex = 0

        connectedCentral = central

        sendData()
    }


    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        os_log("Central unsubscribed from characteristic")
        connectedCentral = nil
    }


    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        sendData()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            guard let requestValue = aRequest.value,
                let stringFromData = String(data: requestValue, encoding: .utf8) else {
                    continue
            }

            os_log("Received write request of %d bytes: %s", requestValue.count, stringFromData)
           // self.textView.text = stringFromData
        }
    }
}

extension PeripheralViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if advertisingSwitch.isOn {
            advertisingSwitch.isOn = false
            peripheralManager.stopAdvertising()
        }
    }


    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }

    @objc
    func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }

}

extension PeripheralViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        self.viewImage[0].image = image
    }
}
