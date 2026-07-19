//
//  HierarchyOutputLimits.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

enum HierarchyOutputLimits {
    /// Default number of class categories returned by screen inspection.
    static let defaultClassLimit = 12

    /// Default number of recommended inspection nodes returned by screen inspection.
    static let defaultTargetLimit = 12

    /// Maximum number of nodes a single query may return.
    static let maximumFindNodeLimit = 100

    /// Maximum allowed pagination cursor length.
    static let maximumPaginationCursorLength = 4_096

    /// Maximum number of nodes a full hierarchy projection may return.
    static let maximumCaptureNodeLimit = 2_000

    /// Maximum number of class categories screen inspection may return.
    static let maximumClassLimit = 100

    /// Maximum number of recommended inspection nodes screen inspection may return.
    static let maximumTargetLimit = 100
}
