//
//  StateVariableInfo.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//


/// Information about a state variable detected during analysis.
struct StateVariableInfo {
    let name: String
    let type: String
    let propertyWrapper: PropertyWrapper
    let viewName: String
    let filePath: String
    let lineNumber: Int
    let hasInitialValue: Bool
}