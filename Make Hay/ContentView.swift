//
//  ContentView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

struct ContentView: View {
    @State private var message = "Make Hay!"

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(message)
            
            Button("Change Text") {
                message = "When Sun Shines!"
            }
            .padding(.top)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
