//
//  ContentView.swift
//  Mission
//
//  Created by Joe Diragi on 2/24/22.
//

import SwiftUI
import Combine
import Foundation
import KeychainAccess
import AlertToast
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Host.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var hosts: FetchedResults<Host>

    @ObservedObject var store: Store = Store()
    private var keychain = Keychain(service: "me.jdiggity.mission")
    
    @State private var isShowingAddAlert = false
    @State private var isShowingAuthAlert = false
    @State private var isShowingFilePicker = false
    
    @State private var nameInput = ""
    @State private var alertInput = ""
    @State private var hostInput = ""
    @State private var portInput = ""
    @State private var userInput = ""
    @State private var passInput = ""
    @State private var filename  = ""
    @State private var isDefault = false
    @State private var downloadDir = ""
    
    var body: some View {
        List(store.torrents, id: \.self) { torrent in
            ListRow(torrent: binding(for: torrent), store: store)
        }
        .toast(isPresenting: $store.isShowingLoading) {
            AlertToast(type: .loading)
        }
        .onAppear(perform: {
            hosts.forEach { h in
                if (h.isDefault) {
                    var config = TransmissionConfig()
                    config.host = h.server
                    config.port = Int(h.port)
                    store.setHost(host: h)
                }
            }
            if (store.host != nil) {
                let info = makeConfig(store: store)
                getDefaultDownloadDir(config: info.config, auth: info.auth, onResponse: { downloadDir in
                    DispatchQueue.main.async {
                        store.defaultDownloadDir = downloadDir
                        self.downloadDir = store.defaultDownloadDir
                    }
                })
                updateList(store: store, update: { vals in
                    DispatchQueue.main.async {
                        store.torrents = vals
                    }
                })
                store.startTimer()
            } else {
                // Create a new host
                isDefault = true
                store.setup = true
            }
        })
        .navigationTitle("Mission")
        .toolbar {
            ToolbarItem(placement: .status) {
                Menu {
                    ForEach(hosts, id: \.self) { host in
                        Button(action: {
                            store.setHost(host: host)
                            store.startTimer()
                            store.isShowingLoading.toggle()
                        }) {
                            let text = host.isDefault ? "\(host.name!) *" : host.name
                            Text(text!)
                        }
                    }
                    Button(action: {store.setup.toggle()}) {
                        Text("Add new...")
                    }
                } label: {
                    Image(systemName: "network")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    self.isShowingAddAlert.toggle()
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        // Add server sheet
        .sheet(isPresented: $store.setup, onDismiss: {}, content: {
            VStack {
                HStack {
                    Text("Connect to Server")
                        .font(.headline)
                        .padding(.bottom, 10)
                        .padding(.top, 20)
                    
                    Button(action: {
                        store.setup.toggle()
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .padding(.top, 20)
                            .padding(.bottom, 10)
                    }).buttonStyle(BorderlessButtonStyle())
                }
                Text("Add a server with it's URL and login")
                    .padding([.leading, .trailing], 20)
                    .padding(.bottom, 5)
                TextField(
                    "Nickname",
                    text: $nameInput
                )
                    .padding([.leading, .trailing], 20)
                    .padding([.top, .bottom], 5)
                TextField(
                    "Hostname (no http://)",
                    text: $hostInput
                )
                    .padding([.leading, .trailing], 20)
                    .padding([.top, .bottom], 5)
                TextField(
                    "Port",
                    text: $portInput
                )
                    .padding([.leading, .trailing], 20)
                    .padding([.top, .bottom], 5)
                TextField(
                    "Username",
                    text: $userInput
                )
                    .padding([.leading, .trailing], 20)
                    .padding([.top, .bottom], 5)
                SecureField(
                    "Password",
                    text: $passInput
                )
                    .padding([.leading, .trailing], 20)
                    .padding([.top, .bottom], 5)
                HStack {
                    Toggle("Make default", isOn: $isDefault)
                        .padding(.leading, 20)
                        .padding(.bottom, 10)
                        .disabled(store.host == nil)
                    Spacer()
                    Button("Submit") {
                        // TODO: If there are no servers yet, make this one default.
                        // Save host
                        let newHost = Host(context: viewContext)
                        newHost.name = nameInput
                        newHost.server = hostInput
                        newHost.port = Int16(portInput)!
                        newHost.username = userInput
                        newHost.isDefault = isDefault
                        
                        // Make sure nobody else is default
                        if (isDefault) {
                            hosts.forEach { h in
                                if (h.isDefault) {
                                    h.isDefault.toggle()
                                }
                            }
                        }
                        
                        try? viewContext.save()
                        
                        // Save password to keychain
                        let keychain = Keychain(service: "me.jdiggity.mission")
                        keychain[nameInput] = passInput
                        
                        // Reset fields
                        nameInput = ""
                        hostInput = ""
                        portInput = ""
                        userInput = ""
                        passInput = ""
                        
                        // Update the view
                        store.setHost(host: newHost)
                        store.startTimer()
                        store.isShowingLoading.toggle()
                        store.setup.toggle()
                    }
                    .padding([.leading, .trailing], 20)
                    .padding(.top, 5)
                    .padding(.bottom, 10)
                }
            }
        })
        // Add torrent alert
        .sheet(isPresented: $isShowingAddAlert, onDismiss: {}, content: {
            VStack {
                HStack {
                    Text("Add Torrent")
                        .font(.headline)
                        .padding(.leading, 20)
                        .padding(.bottom, 10)
                        .padding(.top, 20)
                    Button(action: {
                        self.isShowingAddAlert.toggle()
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .padding(.top, 20)
                            .padding(.bottom, 10)
                            .padding(.leading, 20)
                    }).buttonStyle(BorderlessButtonStyle())
                }
                
                Text("Add either a magnet link or .torrent file.")
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: 200, alignment: .center)
                    .font(.body)
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                
                TextField(
                    "Magnet link",
                    text: $alertInput
                ).onSubmit {
                    // TODO: Validate entry
                }.padding()
                
                TextField(
                    "Download directory",
                    text: $downloadDir
                ).padding()
                
                HStack {
                    Button("Upload file") {
                        // Show file chooser panel
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.torrent]
                        
                        if panel.runModal() == .OK {
                            // Convert the file to a base64 string
                            let fileData = try! Data.init(contentsOf: panel.url!)
                            let fileStream: String = fileData.base64EncodedString(options: NSData.Base64EncodingOptions.init(rawValue: 0))
                            
                            let info = makeConfig(store: store)
                            
                            addTorrent(fileUrl: fileStream, saveLocation: downloadDir, auth: info.auth, file: true, config: info.config, onAdd: { response in
                                if response == TransmissionResponse.success {
                                    self.isShowingAddAlert.toggle()
                                }
                            })
                        }
                    }
                    .padding()
                    Spacer()
                    Button("Submit") {
                        // Send the magnet link to the server
                        let info = makeConfig(store: store)
                        addTorrent(fileUrl: alertInput, saveLocation: downloadDir, auth: info.auth, file: false, config: info.config, onAdd: { response in
                            if response == TransmissionResponse.success {
                                self.isShowingAddAlert.toggle()
                            }
                        })
                    }.padding()
                }
                
            }.interactiveDismissDisabled(false)
        })
    }
    
    func binding(for torrent: Torrent) -> Binding<Torrent> {
        guard let scrumIndex = store.torrents.firstIndex(where: { $0.id == torrent.id }) else {
            fatalError("Can't find in array")
        }
        return $store.torrents[scrumIndex]
    }
}

/// Updates the list of torrents when called
func updateList(store: Store, update: @escaping ([Torrent]) -> Void) {
    let info = makeConfig(store: store)
    getTorrents(config: info.config, auth: info.auth, onReceived: { torrents in
        update(torrents!)
        DispatchQueue.main.async {
            store.isShowingLoading = false
        }
    })
}

/// Function for generating config and auth for API calls
/// - Parameter store: The current `Store` containing session information needed for creating the config.
/// - Returns a tuple containing the requested `config` and `auth`
func makeConfig(store: Store) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    // Send the file to the server
    var config = TransmissionConfig()
    config.host = store.host?.server
    config.port = Int(store.host!.port)
    let keychain = Keychain(service: "me.jdiggity.mission")
    let password = keychain[store.host!.name!]
    let auth = TransmissionAuth(username: store.host!.username!, password: password!)
    
    return (config: config, auth: auth)
}


// This is needed to silence buildtime warnings related to the filepicker.
// `.allowedFileTypes` was deprecated in favor of this attrocity. No comment <3
extension UTType {
    static var torrent: UTType {
        UTType.types(tag: "torrent", tagClass: .filenameExtension, conformingTo: nil).first!
    }
}
