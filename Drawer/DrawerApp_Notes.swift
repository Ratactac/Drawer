// DrawerApp_Notes.swift
// Système de notes complet

import SwiftUI
import AppKit

// MARK: - Notes Panel
struct NotesPanel: View {
    @State private var notes: [Note] = UserDefaults.standard.loadNotes()
    @State private var selectedNoteId: UUID?
    @State private var showNotesList = false
    @AppStorage("notesColor") private var notesColor: String = "yellow"
    
    var backgroundColor: Color {
        switch notesColor {
        case "yellow": return Color(red: 1, green: 0.98, blue: 0.82)
        case "blue": return Color(red: 0.88, green: 0.92, blue: 0.95)
        case "gray": return Color(red: 0.92, green: 0.92, blue: 0.92)
        case "green": return Color(red: 0.88, green: 0.95, blue: 0.88)
        case "black": return Color.black
        case "darkgray": return Color(white: 0.2)
        case "mediumgray": return Color(white: 0.35)
        case "charcoal": return Color(white: 0.15)
        default: return Color(red: 1, green: 0.98, blue: 0.82)
        }
    }

    var isDarkBackground: Bool {
        ["black", "darkgray", "mediumgray", "charcoal"].contains(notesColor)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header avec boutons
            HStack {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDarkBackground ? .white.opacity(0.8) : .black.opacity(0.7))
                
                Spacer()
                
                Button(action: createNewNote) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("New note")
                
                Button(action: { showNotesList.toggle() }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("List of notes")
                
                Text("\(notes.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor.opacity(0.3))
            
            Divider()
            
            // Liste ou éditeur
            if showNotesList {
                NotesListView(
                    notes: $notes,
                    selectedNoteId: $selectedNoteId,
                    showList: $showNotesList,
                    backgroundColor: backgroundColor,
                    isDarkBackground: isDarkBackground
                )
            } else {
                if let noteId = selectedNoteId {
                    NoteEditorView(
                        noteId: noteId,
                        notes: $notes,
                        backgroundColor: backgroundColor,
                        isDarkBackground: isDarkBackground
                    )
                } else {
                    VStack {
                        Spacer()
                        Text("No note selected")
                            .foregroundColor(isDarkBackground ? .white.opacity(0.7) : .gray)
                        Text("Click on + to create a note")
                            .font(.system(size: 11))
                            .foregroundColor(isDarkBackground ? .white.opacity(0.6) : .gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(backgroundColor)
                }
            }
        }
        .background(backgroundColor)
        .overlay(
            VStack(spacing: 0) {
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .orange]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 1, height: 100)

                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 1)
                    .layoutPriority(1)

                LinearGradient(
                    gradient: Gradient(colors: [.orange, .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 1, height: 100)
            },
            alignment: .leading
        )
        .onAppear {
            if notes.isEmpty {
                createNewNote()
            } else if selectedNoteId == nil {
                selectedNoteId = notes.first?.id
            }
        }
    }
    
    private func createNewNote() {
        let newNote = Note()
        notes.insert(newNote, at: 0)
        selectedNoteId = newNote.id
        showNotesList = false
        saveNotes()
    }
    
    private func saveNotes() {
        UserDefaults.standard.saveNotes(notes)
    }
}

// MARK: - Note Editor View
struct NoteEditorView: View {
    let noteId: UUID
    @Binding var notes: [Note]
    let backgroundColor: Color
    let isDarkBackground: Bool
    
    @State private var noteTitle: String = ""
    @State private var noteContent: String = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContentFocused: Bool
    @State private var saveTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            TextField("Untitled Note", text: $noteTitle)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDarkBackground ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .focused($isTitleFocused)
                .onChange(of: noteTitle) { _, newValue in
                    updateNote(title: newValue, content: nil)
                }
            
            Divider()
                .background(isDarkBackground ?
                    Color.white.opacity(0.2) : Color.black.opacity(0.1))
                .padding(.horizontal, 12)
            
            ZStack(alignment: .topLeading) {
                if noteContent.isEmpty && !isContentFocused {
                    Text("Start typing...")
                        .font(.system(size: 13))
                        .foregroundColor(isDarkBackground ?
                            Color.white.opacity(0.3) : Color.gray)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $noteContent)
                    .font(.system(size: 13))
                    .foregroundColor(isDarkBackground ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .focused($isContentFocused)
                    .onChange(of: noteContent) { _, newValue in
                        updateNote(title: nil, content: newValue)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            HStack {
                Text("Modified: \(formatDate(notes.first { $0.id == noteId }?.modifiedDate ?? Date()))")
                    .font(.system(size: 10))
                    .foregroundColor(isDarkBackground ?
                        Color.white.opacity(0.5) : Color.gray.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(backgroundColor)
        .onAppear {
            loadNote()
        }
    }
    
    private func loadNote() {
        if let note = notes.first(where: { $0.id == noteId }) {
            noteTitle = note.title
            noteContent = note.content
        }
    }
    
    private func updateNote(title: String?, content: String?) {
        if let index = notes.firstIndex(where: { $0.id == noteId }) {
            if let title = title {
                notes[index].title = title
            }
            if let content = content {
                notes[index].content = content
            }
            notes[index].modifiedDate = Date()
            
            debounceNoteSave()
        }
    }
    
    private func debounceNoteSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            UserDefaults.standard.saveNotes(notes)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current

        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday, " + formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Notes List View
struct NotesListView: View {
    @Binding var notes: [Note]
    @Binding var selectedNoteId: UUID?
    @Binding var showList: Bool
    let backgroundColor: Color
    let isDarkBackground: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(notes) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isDarkBackground ? .white : .black)
                                .lineLimit(1)
                            
                            if !note.content.isEmpty {
                                Text(note.preview)
                                    .font(.system(size: 11))
                                    .foregroundColor(isDarkBackground ?
                                        .white.opacity(0.7) : .gray)
                                    .lineLimit(2)
                            }
                            
                            Text(note.formattedDate)
                                .font(.system(size: 10))
                                .foregroundColor(isDarkBackground ?
                                    .white.opacity(0.5) : .gray.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            deleteNote(note)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedNoteId == note.id ? Color.blue.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        selectedNoteId = note.id
                        showList = false
                    }
                }
            }
        }
        .background(backgroundColor)
    }
    
    private func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if selectedNoteId == note.id {
            selectedNoteId = notes.first?.id
        }
        UserDefaults.standard.saveNotes(notes)
    }
}
