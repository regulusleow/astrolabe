//
//  AndroidInspectionStrategyTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidInspection
import AstrolabeCLI
import XCTest

final class AndroidInspectionStrategyTests: XCTestCase {
    func testRoleClassifierRecognizesAndroidSemanticControls() {
        let classifier = AndroidNodeSemanticRoleClassifier()

        XCTAssertEqual(
            classifier.roles(for: node(
                role: "button",
                className: "android.widget.Button"
            )),
            [.button, .control, .text]
        )
        XCTAssertEqual(
            classifier.roles(for: node(
                role: "textInput",
                className: "android.widget.EditText"
            )),
            [.input, .text]
        )
        XCTAssertEqual(
            classifier.roles(for: node(
                role: "scroll",
                className: "androidx.recyclerview.widget.RecyclerView"
            )),
            [.list, .scroll]
        )
        XCTAssertEqual(
            classifier.roles(for: node(
                role: "image",
                className: "android.widget.ImageView"
            )),
            [.image]
        )
        XCTAssertEqual(
            classifier.roles(for: node(
                role: "toggle",
                className: "android.widget.Switch"
            )),
            [.control, .text]
        )
    }

    func testDetailMapperProvidesStableCrossPlatformSemantics() {
        let mapper = AndroidNodeDetailAttributeSemanticMapper()

        XCTAssertEqual(
            mapper.semantics(
                forIdentifier: "android.view.frameInScreen",
                appId: "android:test"
            )?.path,
            "layout.frameInScreen"
        )
        XCTAssertEqual(
            mapper.semantics(
                forIdentifier: "android.text.fontSize",
                appId: "android:test"
            )?.name,
            "fontSize"
        )
        XCTAssertEqual(
            mapper.semantics(
                forIdentifier: "android.image.scaleType",
                appId: "android:test"
            )?.path,
            "image.scaleType"
        )
        XCTAssertNil(
            mapper.semantics(
                forIdentifier: "android.unknown.value",
                appId: "android:test"
            )
        )
    }

    func testIssueInterpreterGroupsAndroidSemanticChanges() {
        let interpreter = AndroidNodeDetailSemanticIssueInterpreter()

        XCTAssertEqual(
            interpreter.issueName(for: "scaleType", appId: "android:test"),
            "contentModeChanged"
        )
        XCTAssertEqual(
            interpreter.issueName(for: "checked", appId: "android:test"),
            "controlStateChanged"
        )
        XCTAssertEqual(
            interpreter.issueName(for: "fontSize", appId: "android:test"),
            "fontSizeChanged"
        )
    }

    func testQualityPolicyExcludesStructuralRootsAndPrioritizesAppViews() {
        let policy = AndroidScreenInspectionTargetQualityPolicy()
        let frame = ScreenInspectionFrame(x: 0, y: 0, width: 100, height: 100)

        XCTAssertFalse(
            policy.isEligible(
                ScreenInspectionTargetEligibilityContext(
                    className: "com.android.internal.policy.DecorView",
                    semanticRoles: [.window],
                    frame: frame,
                    screenFrame: frame,
                    hasText: false
                )
            )
        )
        XCTAssertEqual(
            policy.priority(
                className: "com.example.ProfileCardView",
                semanticRoles: [.image],
                reason: .visibleNode
            ),
            1
        )
        XCTAssertEqual(
            policy.priority(
                className: "androidx.recyclerview.widget.RecyclerView",
                semanticRoles: [.list, .scroll],
                reason: .visibleNode
            ),
            0
        )
    }

    private func node(role: String, className: String) -> [String: Any] {
        [
            "role": role,
            "className": className,
            "classChain": [className]
        ]
    }
}
